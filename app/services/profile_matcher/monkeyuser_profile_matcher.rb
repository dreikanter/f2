module ProfileMatcher
  class MonkeyuserProfileMatcher < Base
    match_specificity 100

    MONKEYUSER_DOMAIN = "monkeyuser.com"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      [MONKEYUSER_DOMAIN, "www.#{MONKEYUSER_DOMAIN}"].include?(uri.host)
    end
  end
end
