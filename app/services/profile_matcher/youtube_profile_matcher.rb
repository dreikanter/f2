module ProfileMatcher
  class YoutubeProfileMatcher < DomainMatcher
    match_specificity 100

    match_domains "youtube.com", "youtu.be"
  end
end
