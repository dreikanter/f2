module ProfileMatcher
  class SmbcProfileMatcher < Base
    input_shape :url
    match_specificity 100

    SMBC_DOMAIN = "smbc-comics.com"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      uri.host&.end_with?(SMBC_DOMAIN)
    end
  end
end
