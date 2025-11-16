module ProfileMatcher
  class XkcdProfileMatcher < Base
    XKCD_DOMAIN = "xkcd.com"

    def self.profile_key
      "xkcd"
    end

    def match?
      return false if url.blank?

      uri = URI.parse(url)
      uri.host&.end_with?(XKCD_DOMAIN)
    end
  end
end
