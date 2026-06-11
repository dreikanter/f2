module ProfileMatcher
  class LitterboxProfileMatcher < Base
    input_shape :url
    match_specificity 100

    LITTERBOX_HOSTS = %w[litterboxcomics.com www.litterboxcomics.com].freeze
    FEEDBURNER_DOMAIN = "feedburner.com"
    LITTERBOX_PATH_PATTERN = "litterboxcomics"

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
      (uri.host == FEEDBURNER_DOMAIN || uri.host&.end_with?(".#{FEEDBURNER_DOMAIN}")) &&
        uri.path.to_s.include?(LITTERBOX_PATH_PATTERN)
    end
  end
end
