module ProfileMatcher
  class XkcdProfileMatcher < Base
    input_shape :url
    match_specificity 100

    XKCD_DOMAIN = "xkcd.com"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      uri.host&.end_with?(XKCD_DOMAIN)
    end
  end
end
