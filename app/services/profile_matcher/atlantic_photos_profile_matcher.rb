module ProfileMatcher
  class AtlanticPhotosProfileMatcher < DomainMatcher
    match_specificity 100
    match_domains "theatlantic.com"

    def match?
      super && URI.parse(input).path.match?(%r{\A/feed/channel/(?:photo|photography)/\z})
    end
  end
end
