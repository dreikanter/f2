module ProfileMatcher
  class PhdcomicsProfileMatcher < DomainMatcher
    match_specificity 100
    match_domains "phdcomics.com"

    def match?
      return false if input.blank?
      return true if super

      uri = URI.parse(input)
      uri.host == "feeds.feedburner.com" && uri.path == "/PhdComics"
    end
  end
end
