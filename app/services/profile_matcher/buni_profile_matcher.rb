module ProfileMatcher
  class BuniProfileMatcher < Base
    input_shape :url
    match_specificity 100

    BUNI_DOMAIN = "bunicomic.com"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      [BUNI_DOMAIN, "www.#{BUNI_DOMAIN}"].include?(uri.host)
    end
  end
end
