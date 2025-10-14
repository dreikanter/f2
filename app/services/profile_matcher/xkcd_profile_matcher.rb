module ProfileMatcher
  class XkcdProfileMatcher < Base
    XKCD_DOMAIN = "xkcd.com"

    def match?
      return false if url.blank?

      uri = URI.parse(url)
      uri.host&.end_with?(XKCD_DOMAIN)
    rescue URI::InvalidURIError
      false
    end
  end
end
