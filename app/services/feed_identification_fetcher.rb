class FeedIdentificationFetcher
  # A hard fetch failure: the source returned no usable response, as opposed to a
  # page that loads but fits no structured profile (which falls back to the AI
  # option). Every subclass persists the "fetch_failed" error code (the UI
  # resolves it to text via I18n); the class and its message exist only for the
  # logs.
  class FetchError < StandardError; end
  class UnreachableError < FetchError; end    # no answer: DNS, refused, or timeout
  class RedirectLimitError < FetchError; end  # followed too many redirects

  # Reachable, but answered non-2xx. Carries the status for the log.
  class ResponseStatusError < FetchError
    attr_reader :status

    def initialize(status)
      @status = status
      super("HTTP #{status}")
    end
  end

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
  rescue FetchError => e
    # Expected (a bad or unreachable source): log with detail for debugging, but
    # don't report it as a bug. e.message carries the status or underlying cause.
    @logger.info("Feed identification fetch failed for #{sanitize_input_for_logging(@input)}: #{e.class} (#{e.message})")
    feed_identification.update!(status: :failed, candidates: [], error: "fetch_failed")
  rescue StandardError => e
    # Unexpected: report it as a bug, then surface a neutral code.
    sanitized = sanitize_input_for_logging(@input)
    @logger.error("Feed identification failed for #{sanitized}: #{e.class} - #{e.message}")
    Rails.error.report(e, context: { input: sanitized })
    feed_identification.update!(status: :failed, candidates: [], error: "internal_error")
  end

  private

  # Fetch the URL body for inspection by URL matchers; skip the fetch entirely for
  # query inputs since structured URL detection doesn't apply. Translates the HTTP
  # layer's failures into FetchError subclasses, keeping the original error as the
  # message (and as #cause) for diagnosis.
  def fetch_body_for_input
    return nil if InputClassifier.classify(@input) != :url

    response = http_client.get(@input)
    raise ResponseStatusError.new(response.status) unless response.success?

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

  # Serialize each candidate with its self-test verdict. Non-AI candidates run
  # the real pipeline; AI candidates are never tested (detection stays LLM-free).
  def tested_candidates(candidates)
    candidates.map { |candidate| candidate.as_json.merge(test_result(candidate)) }
  end

  def test_result(candidate)
    return { "test_status" => "not_tested" } if candidate.depends_on_ai

    result = CandidateTester.new(
      user: @user,
      input: @input,
      profile_key: candidate.profile_key,
      http_client: http_client
    ).call

    {
      "test_status" => result.status.to_s,
      "tested_at" => Time.current.iso8601,
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
