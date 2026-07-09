module ProfileMatcher
  class LitterboxProfileMatcher < Base
    match_specificity 100

    LITTERBOX_HOSTS = %w[litterboxcomics.com www.litterboxcomics.com].freeze
    FEEDBURNER_HOST = "feeds.feedburner.com"
    LITTERBOX_FEEDBURNER_PATH = "/litterboxcomics/"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      return false if uri.host.blank?

      litterbox_host?(uri) || feedburner_litterbox?(uri)
    end

    private

    def litterbox_host?(uri)
      LITTERBOX_HOSTS.include?(uri.host)
    end

    def feedburner_litterbox?(uri)
      uri.host == FEEDBURNER_HOST &&
        uri.path.to_s.start_with?(LITTERBOX_FEEDBURNER_PATH)
    end
  end
end
