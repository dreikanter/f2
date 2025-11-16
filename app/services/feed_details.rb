class FeedDetails
  CACHE_EXPIRES_IN = 10.minutes

  def initialize(user:, url:, cache: Rails.cache, logger: Rails.logger)
    @user = user
    @url = url
    @cache = cache
    @logger = logger
  end

  def identify
    cache_key = FeedIdentificationCache.key_for(@user.id, @url)

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

        @cache.write(
          cache_key,
          {
            status: "success",
            url: @url,
            feed_profile_key: profile_key,
            title: title
          },
          expires_in: CACHE_EXPIRES_IN
        )
      else
        @cache.write(
          cache_key,
          {
            status: "failed",
            url: @url,
            error: "Could not identify feed profile"
          },
          expires_in: CACHE_EXPIRES_IN
        )
      end
    rescue => e
      @logger.error("Feed identification failed for #{@url}: #{e.message}")
      @cache.write(
        cache_key,
        {
          status: "failed",
          url: @url,
          error: "An error occurred while identifying the feed"
        },
        expires_in: CACHE_EXPIRES_IN
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
