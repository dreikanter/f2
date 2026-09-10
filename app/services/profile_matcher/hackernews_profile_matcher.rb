module ProfileMatcher
  class HackernewsProfileMatcher < DomainMatcher
    match_specificity 100
    match_domains "news.ycombinator.com"

    def match?
      super && URI.parse(input).path == "/best"
    end
  end
end
