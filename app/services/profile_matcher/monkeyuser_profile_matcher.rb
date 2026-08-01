module ProfileMatcher
  class MonkeyuserProfileMatcher < DomainMatcher
    match_specificity 100

    match_domains "monkeyuser.com"
  end
end
