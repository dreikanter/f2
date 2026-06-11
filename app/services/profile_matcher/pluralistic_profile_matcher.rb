module ProfileMatcher
  class PluralisticProfileMatcher < Base
    input_shape :url
    match_specificity 100

    PLURALISTIC_DOMAIN = "pluralistic.net"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      uri.host == PLURALISTIC_DOMAIN || uri.host&.end_with?(".#{PLURALISTIC_DOMAIN}")
    end
  end
end
