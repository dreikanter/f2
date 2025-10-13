module ProfileMatcher
  # Matcher for xkcd feeds
  class XkcdProfileMatcher < Base
    XKCD_DOMAIN = "xkcd.com"

    # Determines if the feed is an xkcd feed
    # @return [Boolean] true if the URL is from xkcd.com
    def match?
      return false if url.blank?

      uri = URI.parse(url)
      uri.host&.end_with?(XKCD_DOMAIN)
    rescue URI::InvalidURIError
      false
    end
  end
end
