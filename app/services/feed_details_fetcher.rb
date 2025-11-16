class FeedDetailsFetcher
  def initialize(user:, url:, logger: Rails.logger)
    @user = user
    @url = url
    @logger = logger
  end

  def identify
    feed_detail = FeedDetail.find_or_initialize_by(user: @user, url: @url)

    begin
      response = http_client.get(@url)

      unless response.success?
        raise HttpClient::Error, "HTTP request failed with status #{response.status}"
      end

      detector = FeedProfileDetector.new(@url, response)
      matcher_class = detector.detect

      if matcher_class
        profile_key = matcher_class.name.demodulize.gsub(/ProfileMatcher$/, "").underscore
        title = extract_title(profile_key, @url, response)

        feed_detail.update!(
          status: :success,
          feed_profile_key: profile_key,
          title: title,
          error: nil
        )
      else
        feed_detail.update!(
          status: :failed,
          feed_profile_key: nil,
          title: nil,
          error: "Could not identify feed profile"
        )
      end
    rescue => e
      @logger.error("Feed identification failed for #{@url}: #{e.class} - #{e.message}")
      feed_detail.update!(
        status: :failed,
        feed_profile_key: nil,
        title: nil,
        error: "An error occurred while identifying the feed"
      )
    end
  end

  private

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
