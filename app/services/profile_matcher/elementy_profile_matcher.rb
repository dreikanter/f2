module ProfileMatcher
  class ElementyProfileMatcher < Base
    match_specificity 100

    ELEMENTY_DOMAIN = "elementy.ru"

    def match?
      return false if input.blank?

      uri = URI.parse(input)
      [ELEMENTY_DOMAIN, "www.#{ELEMENTY_DOMAIN}"].include?(uri.host)
    end
  end
end
