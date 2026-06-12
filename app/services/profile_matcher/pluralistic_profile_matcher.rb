module ProfileMatcher
  class PluralisticProfileMatcher < Base
    input_shape :url
    match_specificity 100

    PLURALISTIC_DOMAIN = "pluralistic.net"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      [PLURALISTIC_DOMAIN, "www.#{PLURALISTIC_DOMAIN}"].include?(uri.host)
    end
  end
end
