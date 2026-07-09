module ProfileMatcher
  class TomorrowsProfileMatcher < Base
    match_specificity 100

    TOMORROWS_DOMAIN = "365tomorrows.com"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      [TOMORROWS_DOMAIN, "www.#{TOMORROWS_DOMAIN}"].include?(uri.host)
    end
  end
end
