class FeedIdentificationJob < ApplicationJob
  queue_as :default

  def perform(user_id, url)
    user = User.find_by(id: user_id)

    unless user
      Rails.logger.warn("FeedIdentificationJob skipped: User #{user_id} not found (job_id: #{job_id}, url: #{url})")
      return
    end

    cache_key = FeedIdentificationCache.key_for(user_id, url)

    begin
      response = http_client.get(url)
      detector = FeedProfileDetector.new(url, response)
      matcher_class = detector.detect

      if matcher_class
        profile_key = matcher_class.name.demodulize.gsub(/ProfileMatcher$/, "").underscore
        title = extract_title(profile_key, url, response)

        Rails.cache.write(
          cache_key,
          {
            status: "success",
            url: url,
            feed_profile_key: profile_key,
            title: title
          },
          expires_in: 10.minutes
        )
      else
        Rails.cache.write(
          cache_key,
          {
            status: "failed",
            url: url,
            error: "Could not identify feed profile"
          },
          expires_in: 10.minutes
        )
      end
    rescue => e
      Rails.logger.error("Feed identification failed for #{url}: #{e.message}")
      Rails.cache.write(
        cache_key,
        {
          status: "failed",
          url: url,
          error: "An error occurred while identifying the feed"
        },
        expires_in: 10.minutes
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
    Rails.logger.warn("Title extraction failed for #{url}: #{e.message}")
    nil
  end
end
