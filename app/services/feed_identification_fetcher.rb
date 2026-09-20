class FeedIdentificationFetcher
  # A fetch that yielded no usable response. UnreachableError settles the row
  # as unreachable (transient, retryable); every other FetchError settles it
  # as no_feed (terminal "no feed here"). The messages are for logs.
  class FetchError < StandardError; end
  class UnreachableError < FetchError; end    # no answer: DNS, refused, or timeout
  class RedirectLimitError < FetchError; end  # followed too many redirects

  class ResponseStatusError < FetchError; end # reachable, but answered non-2xx

  def initialize(feed_identification:, run_id:)
    @feed_identification = feed_identification
    @run_id = run_id
    @user = feed_identification.user
    @input = feed_identification.input
    @event = Event.where("metadata -> 'stats' ->> 'run_id' = ?", run_id).create_or_find_by!(type: "feed_identification") do |event|
      event.assign_attributes(level: :debug, user: @user,
                              subject: feed_identification, message: sanitize_url(@input),
                              metadata: { stats: { run_id: run_id, source_url: sanitize_url(@input) } })
    end
  end

  def call
    @started_at = Time.current
    response = fetch_response_for_input
    candidates = identify_candidates(response)
    settle(status: settled_status(candidates), candidates: candidates)
  rescue FetchError => e
    # Transport failures stay retryable; other fetch failures mean no feed.
    status = e.is_a?(UnreachableError) ? :unreachable : :no_feed
    settle(status: status, candidates: [], error: e)
  rescue StandardError => e
    # Unexpected: report it as a bug, then settle on the terminal state.
    Rails.error.report(e, context: { input: sanitize_url(@input) })
    settle(status: :no_feed, candidates: [], error: e)
  end

  private

  # The input may be a raw address (the entry form's silent scheme-fix), so
  # refuse non-public targets before the GET (SSRF). Redirect hops are not
  # validated on this fetch.
  def fetch_response_for_input
    raise FetchError, "blocked non-public URL" unless PublicUrl.safe?(@input)

    response = fetch_response(@input)
    raise ResponseStatusError, "HTTP #{response.status}" unless response.success?

    response
  rescue HttpClient::TooManyRedirectsError => e
    raise RedirectLimitError, e.message
  rescue HttpClient::Error => e
    raise UnreachableError, e.message
  end

  # Fall back to advertised feeds unless a direct candidate actually reads
  # the source; a matcher can trip on markup no profile parses.
  def identify_candidates(response)
    direct = tested_candidates(FeedProfileDetector.call(input: @input, fetched_body: response.body).candidates, input: @input)
    return direct if direct.any? { |candidate| working?(candidate) }

    direct + discovered_candidates(response)
  end

  # Stops at the first URL with a working candidate: the chooser, the
  # preview, and the edit confirmation expect one source URL per
  # identification. Relative links resolve against where the fetch landed,
  # not the typed URL.
  def discovered_candidates(response)
    candidates = []
    base_url = response.url.presence || @input

    FeedLinkDiscovery.call(response.body, base_url: base_url).each do |feed_url|
      feed_body = fetch_discovered_body(feed_url)
      next if feed_body.nil?

      detected = FeedProfileDetector.call(input: feed_url, fetched_body: feed_body).candidates
      tested = tested_candidates(detected, input: feed_url)
                 .map { |attributes| attributes.merge("resolved_url" => feed_url) }
      candidates.concat(tested)
      break if tested.any? { |attributes| working?(attributes) }
    end

    candidates
  end

  def working?(candidate_attributes)
    FeedIdentification::Candidate.new(candidate_attributes).passed?
  end

  # The settled result of a finished run: a candidate that read the source
  # makes it working; candidates that all died on the network make it
  # unreachable; anything else (no candidates, or none parsed) is no_feed.
  def settled_status(candidates)
    verdicts = candidates.map { |attributes| FeedIdentification::Candidate.new(attributes) }
    return :working if verdicts.any?(&:passed?)
    return :unreachable if verdicts.any? && verdicts.all?(&:unreachable?)

    :no_feed
  end

  # A broken advertised feed is skipped; another may still work. The hrefs
  # are author-controlled, so redirect hops are validated too (SSRF).
  def fetch_discovered_body(feed_url)
    response = fetch_response(feed_url, options: { validate_url: PublicUrl.method(:safe?) })
    response.body if response.success?
  rescue HttpClient::Error
    nil
  end

  def sanitize_url(input)
    uri = URI.parse(input.to_s)
    uri.user = nil
    uri.password = nil
    uri.query = nil
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    "[invalid URL]"
  end

  def settle(status:, candidates:, error: nil)
    @event.with_lock do
      applied = @feed_identification.settle_detection(status: status, candidates: candidates, run_id: @run_id)
      selected = candidates.find { |candidate| working?(candidate) }&.fetch("profile_key")
      summary = [status, selected].compact.join(": ")
      summary += " (discarded)" unless applied
      # A duplicate worker's discarded result must not replace the accepted summary.
      unless @event.details.any? { |detail| detail.dig("stats", "applied") }
        @event.update!(message: "#{summary} · #{sanitize_url(@input)}")
      end
      record_detail(:result, summary, status: status, selected_profile: selected, applied: applied,
                    error: error && "#{error.class}: #{error.message}", total_duration: (Time.current - @started_at).round(3))
      applied
    end
  end

  def fetch_response(url, **options)
    response = http_client.get(url, **options)
    record_detail(:fetch, "HTTP #{response.status}", source_url: url, resolved_url: response.url,
                 http_status: response.status, content_type: response.headers["content-type"], body_bytes: response.body.to_s.bytesize)
    response
  rescue HttpClient::Error => e
    record_detail(:fetch, "#{e.class}: #{e.message}", source_url: url)
    raise
  end

  def record_detail(stage, message, **stats)
    @event.append_detail!(stage: stage, message: sanitize_event_text(message),
                          stats: stats.compact.transform_values { |value| value.is_a?(String) ? sanitize_event_text(value) : value })
  end

  def sanitize_event_text(text)
    text.gsub(%r{https?://[^\s<>"']+}i) { |url| sanitize_url(url) }.truncate(1_000)
  end

  # Self-test each candidate by running the real pipeline against input
  # (the typed URL or a discovered feed URL). Only deterministic profiles
  # appear here: the AI profile registers no matcher.
  def tested_candidates(candidates, input:)
    candidates.map { |candidate| candidate.as_json.merge(test_result(candidate, input: input)) }
  end

  def test_result(candidate, input:)
    result = CandidateTester.new(
      user: @user,
      input: input,
      profile_key: candidate.profile_key,
      http_client: http_client
    ).call

    record_detail(:candidate, "#{candidate.profile_key}: #{result.status}, #{result.posts_found} sampled posts",
                 source_url: input, profile_key: candidate.profile_key, **result.to_h)

    {
      "test_status" => result.status,
      "posts_found" => result.posts_found
    }
  end

  # Per-run cache: matching and candidate testing fetch each URL once.
  def http_client
    @http_client ||= HttpClient.build(
      adapter: HttpClient::CachingAdapter, timeout: 15, max_redirects: 5
    )
  end
end
