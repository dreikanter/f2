class FeedDetailsFetcher
  def initialize(user:, url:, logger: Rails.logger)
    @user = user
    @url = url
    @logger = logger
  end

  def identify
    response = http_client.get(@url)
    raise "HTTP request failed with status #{response.status}" unless response.success?

    matcher_class = FeedProfileDetector.new(@url, response).detect

    if matcher_class
      profile_key = matcher_class.profile_key
      title = extract_title(profile_key, @url, response)
      feed_detail.update!(status: :success, feed_profile_key: profile_key, title: title, error: nil)
    else
      feed_detail.update!(status: :failed, feed_profile_key: nil, title: nil, error: "Unsupported feed profile")
    end
  rescue StandardError => e
    @logger.error("Feed identification failed for #{sanitize_url_for_logging(@url)}: #{e.class} - #{e.message}")
    feed_detail.update!(status: :failed, feed_profile_key: nil, title: nil, error: "An error occurred while identifying the feed")
  end

  private

  def sanitize_url_for_logging(url)
    return "[invalid URL]" if url.blank?

    uri = URI.parse(url)
    # Remove query parameters to avoid logging sensitive data
    uri.query = nil
    uri.to_s
  rescue URI::InvalidURIError
    "[invalid URL]"
  end

  def feed_detail
    @feed_detail ||= begin
      FeedDetail.find_or_create_by!(user: @user, url: @url)
    rescue ActiveRecord::RecordNotUnique
      # Race condition: another process created the record, retry once to get it
      FeedDetail.find_by!(user: @user, url: @url)
    end
  end

  def http_client
    @http_client ||= HttpClient.build(timeout: 15, max_redirects: 5)
  end

  def extract_title(profile_key, url, response)
    title_extractor_class = FeedProfile.title_extractor_class_for(profile_key)
    title_extractor = title_extractor_class.new(url, response)
    title_extractor.title
  rescue => e
    @logger.warn("Title extraction failed for #{url}: #{e.message}")
    nil
  end
end
