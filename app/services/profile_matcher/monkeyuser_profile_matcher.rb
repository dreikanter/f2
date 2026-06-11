module ProfileMatcher
  class MonkeyuserProfileMatcher < Base
    input_shape :url
    match_specificity 100

    MONKEYUSER_DOMAIN = "monkeyuser.com"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      uri.host == MONKEYUSER_DOMAIN || uri.host&.end_with?(".#{MONKEYUSER_DOMAIN}")
    end
  end
end
