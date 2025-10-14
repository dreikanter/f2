# Service for detecting the appropriate feed profile based on URL and content
#
class FeedProfileDetector
  # Matcher classes in order from most specific to most generic
  DETECTION_ORDER = %w[
    ProfileMatcher::XkcdProfileMatcher
    ProfileMatcher::RssProfileMatcher
  ].freeze

  attr_reader :url, :response

  # @param url [String] the feed URL
  # @param response [HttpClient::Response] the HTTP response object
  def initialize(url, response)
    @url = url
    @response = response
  end

  # Detects the appropriate profile for the feed
  # @return [String, nil] the matcher class name or nil if no match found
  def detect
    DETECTION_ORDER.each do |matcher_class_name|
      matcher_class = matcher_class_name.constantize
      matcher = matcher_class.new(url, response)
      return matcher_class if matcher.match?
    end

    nil
  end
end
