module ProfileMatcher
  class XkcdProfileMatcher < DomainMatcher
    match_specificity 100

    match_domains "xkcd.com"
  end
end
