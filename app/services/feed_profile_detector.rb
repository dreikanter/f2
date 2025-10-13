# Service for detecting the appropriate feed profile based on URL and content
#
class FeedProfileDetector
  # Profile keys in order from most specific to most generic
  DETECTION_ORDER = %w[xkcd rss].freeze

  attr_reader :url, :response

  # @param url [String] the feed URL
  # @param response [HttpClient::Response] the HTTP response object
  def initialize(url, response)
    @url = url
    @response = response
  end

  # Detects the appropriate profile for the feed
  # @return [String, nil] the profile key or nil if no match found
  def detect
    DETECTION_ORDER.each do |profile_key|
      matcher_class = matcher_class_for(profile_key)
      matcher = matcher_class.new(url, response)
      return profile_key if matcher.match?
    end

    nil
  end

  private

  def matcher_class_for(profile_key)
    ClassResolver.resolve("ProfileMatcher", profile_key)
  end
end
