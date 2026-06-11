module ProfileMatcher
  class AerostatProfileMatcher < Base
    input_shape :url
    match_specificity 100

    AEROSTAT_DOMAIN = "aerostatbg.ru"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      uri.host == AEROSTAT_DOMAIN || uri.host&.end_with?(".#{AEROSTAT_DOMAIN}")
    end
  end
end
