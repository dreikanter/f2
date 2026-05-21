class FeedIdentificationFetcher
  def initialize(user:, url:, logger: Rails.logger)
    @user = user
    @url = url
    @logger = logger
  end

  def identify
    body = fetch_body_for_url

    result = FeedProfileDetector.call(input: @url, fetched_body: body)

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
    @logger.error("Feed identification failed for #{sanitize_url_for_logging(@url)}: #{e.class} - #{e.message}")
    feed_identification.update!(status: :failed, candidates: [], error: "An error occurred while identifying the feed")
  end

  private

  # Fetch the URL body for inspection by URL matchers; skip the fetch
  # entirely for handle / query inputs since structured URL detection
  # doesn't apply.
  def fetch_body_for_url
    return nil if InputClassifier.classify(@url) != :url

    response = http_client.get(@url)
    raise "HTTP request failed with status #{response.status}" unless response.success?

    response.body
  end

  def sanitize_url_for_logging(url)
    return "[invalid URL]" if url.blank?

    uri = URI.parse(url)
    # Remove query parameters to avoid logging sensitive data
    uri.query = nil
    uri.to_s
  rescue URI::InvalidURIError
    "[invalid URL]"
  end

  def feed_identification
    @feed_identification ||= begin
      FeedIdentification.find_or_create_by!(user: @user, url: @url)
    rescue ActiveRecord::RecordNotUnique
      # Race condition: another process created the record, retry once to get it
      FeedIdentification.find_by!(user: @user, url: @url)
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
