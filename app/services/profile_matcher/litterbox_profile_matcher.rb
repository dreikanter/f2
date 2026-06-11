module ProfileMatcher
  class LitterboxProfileMatcher < Base
    input_shape :url
    match_specificity 100

    LITTERBOX_DOMAIN = "litterboxcomics.com"
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
      uri.host == LITTERBOX_DOMAIN || uri.host.end_with?(".#{LITTERBOX_DOMAIN}")
    end

    def feedburner_litterbox?(uri)
      (uri.host == FEEDBURNER_DOMAIN || uri.host&.end_with?(".#{FEEDBURNER_DOMAIN}")) &&
        uri.path.to_s.include?(LITTERBOX_PATH_PATTERN)
    end
  end
end
