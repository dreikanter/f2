module ProfileMatcher
  class WumoProfileMatcher < DomainMatcher
    match_specificity 100

    match_domains "wumo.com"

    def match?
      super && URI.parse(input).path.match?(%r{\A/wumo(?:/|\z)})
    end
  end
end
