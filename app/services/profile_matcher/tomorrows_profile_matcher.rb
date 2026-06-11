module ProfileMatcher
  class TomorrowsProfileMatcher < Base
    input_shape :url
    match_specificity 100

    TOMORROWS_DOMAIN = "365tomorrows.com"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      uri.host == TOMORROWS_DOMAIN || uri.host&.end_with?(".#{TOMORROWS_DOMAIN}")
    end
  end
end
