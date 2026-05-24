class FeedIdentificationFetcher
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
        candidates: serialize_candidates(result.candidates),
        error: nil
      )
    else
      feed_identification.update!(status: :failed, candidates: [], error: "Unsupported feed profile")
    end
  rescue StandardError => e
    @logger.error("Feed identification failed for #{sanitize_input_for_logging(@input)}: #{e.class} - #{e.message}")
    feed_identification.update!(status: :failed, candidates: [], error: "An error occurred while identifying the feed")
  end

  private

  # Fetch the URL body for inspection by URL matchers; skip the fetch
  # entirely for query inputs since structured URL detection
  # doesn't apply.
  def fetch_body_for_input
    return nil if InputClassifier.classify(@input) != :url

    response = http_client.get(@input)
    raise "HTTP request failed with status #{response.status}" unless response.success?

    response.body
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

  def http_client
    @http_client ||= HttpClient.build(timeout: 15, max_redirects: 5)
  end

  def serialize_candidates(candidates)
    candidates.map do |c|
      {
        "profile_key" => c.profile_key,
        "title" => c.title,
        "depends_on_ai" => c.depends_on_ai,
        "rank" => c.rank,
        "rank_reason" => c.rank_reason.to_s
      }
    end
  end
end
