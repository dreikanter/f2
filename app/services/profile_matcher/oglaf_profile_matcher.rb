module ProfileMatcher
  class OglafProfileMatcher < Base
    match_specificity 100

    OGLAF_DOMAIN = "oglaf.com"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      [OGLAF_DOMAIN, "www.#{OGLAF_DOMAIN}"].include?(uri.host)
    end
  end
end
