module ProfileMatcher
  class TheycantalkProfileMatcher < Base
    match_specificity 100

    THEYCANTALK_HOSTS = ["theycantalk.com", "www.theycantalk.com"].freeze
    FEEDBURNER_HOST = "feeds.feedburner.com"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      theycantalk_host?(uri) || feedburner_theycantalk_host?(uri)
    end

    private

    def theycantalk_host?(uri)
      THEYCANTALK_HOSTS.include?(uri.host)
    end

    def feedburner_theycantalk_host?(uri)
      uri.host == FEEDBURNER_HOST && uri.path.to_s.include?("theycantalk")
    end
  end
end
