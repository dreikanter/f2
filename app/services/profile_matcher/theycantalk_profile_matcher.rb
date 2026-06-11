module ProfileMatcher
  class TheycantalkProfileMatcher < Base
    input_shape :url
    match_specificity 100

    THEYCANTALK_DOMAIN = "theycantalk.com"
    FEEDBURNER_DOMAIN = "feedburner.com"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      theycantalk_host?(uri) || feedburner_theycantalk_host?(uri)
    end

    private

    def theycantalk_host?(uri)
      uri.host == THEYCANTALK_DOMAIN || uri.host&.end_with?(".#{THEYCANTALK_DOMAIN}")
    end

    def feedburner_theycantalk_host?(uri)
      (uri.host == FEEDBURNER_DOMAIN || uri.host&.end_with?(".#{FEEDBURNER_DOMAIN}")) &&
        uri.path.to_s.include?("theycantalk")
    end
  end
end
