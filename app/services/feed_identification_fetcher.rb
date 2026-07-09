class FeedIdentificationFetcher
  # A fetch that yielded no usable response. UnreachableError (couldn't connect)
  # persists as "unreachable" and reads as a transient retry; every other
  # FetchError (bad status, redirect loop, a blocked non-public host) persists as
  # "unreadable" and reads as a terminal "no feed here" (spec §7). The class and
  # its message exist only for the logs.
  class FetchError < StandardError; end
  class UnreachableError < FetchError; end    # no answer: DNS, refused, or timeout
  class RedirectLimitError < FetchError; end  # followed too many redirects

  class ResponseStatusError < FetchError; end # reachable, but answered non-2xx

  def initialize(user:, input:, logger: Rails.logger)
    @user = user
    @input = input
    @logger = logger
  end

  def identify
    body = fetch_body_for_input

    result = FeedProfileDetector.call(input: @input, fetched_body: body)

    if result.candidates.any?
      feed_identification.update!(
        status: :success,
        candidates: tested_candidates(result.candidates),
        error: nil
      )
    else
      feed_identification.update!(status: :failed, candidates: [], error: "unidentifiable")
    end
  rescue UnreachableError => e
    # Couldn't connect (DNS, refused, timeout): genuinely transient, so the UI
    # offers a retry. Expected, so log without reporting it as a bug.
    @logger.info("Feed identification couldn't reach #{sanitize_input_for_logging(@input)}: #{e.class} (#{e.message})")
    feed_identification.update!(status: :failed, candidates: [], error: "unreachable")
  rescue FetchError => e
    # Reached the source but it's unusable (bad status, redirect loop): retrying
    # won't help, so this reads as a terminal "no feed here".
    @logger.info("Feed identification fetch failed for #{sanitize_input_for_logging(@input)}: #{e.class} (#{e.message})")
    feed_identification.update!(status: :failed, candidates: [], error: "unreadable")
  rescue StandardError => e
    # Unexpected: report it as a bug, then surface a neutral code.
    sanitized = sanitize_input_for_logging(@input)
    @logger.error("Feed identification failed for #{sanitized}: #{e.class} - #{e.message}")
    Rails.error.report(e, context: { input: sanitized })
    feed_identification.update!(status: :failed, candidates: [], error: "internal_error")
  end

  private

  # Fetch the source URL body for inspection by the URL matchers. The input is
  # always a canonical URL here (Mode A), so we always fetch. Translates the HTTP
  # layer's failures into FetchError subclasses, keeping the original error as the
  # message (and as #cause) for diagnosis.
  #
  # Refuse a non-public target before the GET (SSRF, spec §8): the silent
  # scheme-fix now lets a bare `169.254.169.254` reach this fetch, so a private,
  # loopback, or metadata address must not be dialed. Redirects that hop into a
  # private range are a separate fetch-layer gap tracked in #920.
  def fetch_body_for_input
    raise FetchError, "blocked non-public URL" unless PublicUrl.safe?(@input)

    response = http_client.get(@input)
    raise ResponseStatusError, "HTTP #{response.status}" unless response.success?

    response.body
  rescue HttpClient::TooManyRedirectsError => e
    raise RedirectLimitError, e.message
  rescue HttpClient::Error => e
    raise UnreachableError, e.message
  end

  def sanitize_input_for_logging(input)
    return "[invalid input]" if input.blank?

    uri = URI.parse(input)
    # Remove query parameters to avoid logging sensitive data
    uri.query = nil
    uri.to_s
  rescue URI::InvalidURIError
    "[invalid input]"
  end

  def feed_identification
    @feed_identification ||= begin
      FeedIdentification.find_or_create_by!(user: @user, input: @input)
    rescue ActiveRecord::RecordNotUnique
      # Race condition: another process created the record, retry once to get it
      FeedIdentification.find_by!(user: @user, input: @input)
    end
  end

  # Serialize each candidate with its self-test verdict from running the real
  # pipeline. Only deterministic profiles can appear here — the AI profile
  # registers no matcher — so detection stays LLM-free.
  def tested_candidates(candidates)
    candidates.map { |candidate| candidate.as_json.merge(test_result(candidate)) }
  end

  def test_result(candidate)
    result = CandidateTester.new(
      user: @user,
      input: @input,
      profile_key: candidate.profile_key,
      http_client: http_client
    ).call

    {
      "test_status" => result.status.to_s,
      "posts_found" => result.posts_found
    }
  end

  # A per-run cache so matching and per-candidate testing fetch each URL once.
  # Scoped to this fetcher instance (one identification run); scheduled refreshes
  # build their own loaders and are unaffected.
  def http_client
    @http_client ||= HttpClient.build(
      adapter: HttpClient::CachingAdapter, timeout: 15, max_redirects: 5
    )
  end
end
