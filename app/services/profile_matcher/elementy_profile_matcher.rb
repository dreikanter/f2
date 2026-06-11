module ProfileMatcher
  class ElementyProfileMatcher < Base
    input_shape :url
    match_specificity 100

    ELEMENTY_DOMAIN = "elementy.ru"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      uri.host == ELEMENTY_DOMAIN || uri.host&.end_with?(".#{ELEMENTY_DOMAIN}")
    end
  end
end
