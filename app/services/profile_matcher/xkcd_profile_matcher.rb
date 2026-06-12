module ProfileMatcher
  class XkcdProfileMatcher < Base
    input_shape :url
    match_specificity 100

    XKCD_DOMAIN = "xkcd.com"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      [XKCD_DOMAIN, "www.#{XKCD_DOMAIN}"].include?(uri.host)
    end
  end
end
