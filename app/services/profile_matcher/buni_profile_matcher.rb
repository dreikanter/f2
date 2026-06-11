module ProfileMatcher
  class BuniProfileMatcher < Base
    input_shape :url
    match_specificity 100

    BUNI_DOMAIN = "bunicomic.com"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      uri.host == BUNI_DOMAIN || uri.host&.end_with?(".#{BUNI_DOMAIN}")
    end
  end
end
