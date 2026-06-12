module ProfileMatcher
  class AerostatProfileMatcher < Base
    input_shape :url
    match_specificity 100

    AEROSTAT_DOMAIN = "aerostatbg.ru"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      [AEROSTAT_DOMAIN, "www.#{AEROSTAT_DOMAIN}"].include?(uri.host)
    end
  end
end
