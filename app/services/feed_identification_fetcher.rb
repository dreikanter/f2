class FeedIdentificationFetcher
  # A fetch that yielded no usable response. UnreachableError settles the row
  # as unreachable (transient, retryable); every other FetchError settles it
  # as no_feed (terminal "no feed here"). The messages are for logs.
  class FetchError < StandardError; end
  class UnreachableError < FetchError; end    # no answer: DNS, refused, or timeout
  class RedirectLimitError < FetchError; end  # followed too many redirects

  class ResponseStatusError < FetchError; end # reachable, but answered non-2xx

  def initialize(feed_identification:, run_id:, logger: Rails.logger)
    @feed_identification = feed_identification
    @run_id = run_id
    @user = feed_identification.user
    @input = feed_identification.input
    @logger = logger
    @diagnostics = { fetches: [], candidate_tests: [] }
  end

  def call
    response = fetch_response_for_input
    candidates = identify_candidates(response)
    settle(status: settled_status(candidates), candidates: candidates)
  rescue UnreachableError => e
    # Transient: the UI offers a retry. Expected, so not reported as a bug.
    @logger.info("Feed identification couldn't reach #{sanitize_input_for_logging(@input)}: #{e.class} (#{e.message})")
    settle(status: :unreachable, candidates: [], error: e)
  rescue FetchError => e
    @logger.info("Feed identification fetch failed for #{sanitize_input_for_logging(@input)}: #{e.class} (#{e.message})")
    settle(status: :no_feed, candidates: [], error: e)
  rescue StandardError => e
    # Unexpected: report it as a bug, then settle on the terminal state.
    Rails.error.report(e, context: { input: sanitize_input_for_logging(@input) })
    settle(status: :no_feed, candidates: [], error: e)
  end

  private

  # The input may be a raw address (the entry form's silent scheme-fix), so
  # refuse non-public targets before the GET (SSRF). Redirect hops are not
  # validated on this fetch.
  def fetch_response_for_input
    raise FetchError, "blocked non-public URL" unless PublicUrl.safe?(@input)

    response = http_client.get(@input)
    record_response(@input, response)
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
    response = http_client.get(feed_url, options: { validate_url: PublicUrl.method(:safe?) })
    record_response(feed_url, response)
    return response.body if response.success?

    @logger.info("Feed discovery skipped #{sanitize_input_for_logging(feed_url)}: HTTP #{response.status}")
    nil
  rescue HttpClient::Error => e
    @diagnostics[:fetches] << { url: feed_url, error: error_details(e) }
    @logger.info("Feed discovery skipped #{sanitize_input_for_logging(feed_url)}: #{e.class} (#{e.message})")
    nil
  end

  def sanitize_input_for_logging(input)
    FeedIdentificationActivity.sanitize_url(input)
  end

  def settle(status:, candidates:, error: nil)
    @diagnostics[:error] = error_details(error) if error
    @feed_identification.settle_detection(status: status, candidates: candidates, run_id: @run_id, diagnostics: @diagnostics)
  end

  def record_response(url, response)
    @diagnostics[:fetches] << {
      url: url,
      resolved_url: response.url,
      http_status: response.status,
      content_type: response.headers["content-type"],
      body_bytes: response.body.to_s.bytesize
    }
  end

  def error_details(error)
    { class: error.class.name, message: error.message.truncate(1_000) }
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

    @diagnostics[:candidate_tests] << result.to_h.merge(profile_key: candidate.profile_key, url: input)

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
