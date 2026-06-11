module ProfileMatcher
  class OglafProfileMatcher < Base
    input_shape :url
    match_specificity 100

    OGLAF_DOMAIN = "oglaf.com"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      uri.host&.end_with?(OGLAF_DOMAIN)
    end
  end
end
