module ProfileMatcher
  class PodcastProfileMatcher < Base
    # Ranks above generic RSS (10): the itunes namespace declaration is a
    # stronger signal than the RSS matcher's scan for XML-like text.
    match_specificity 15

    # Mirrors Feedjira's ITunesRSS detection (namespace declaration outside
    # CDATA), so the profile claims exactly the feeds Feedjira will hand to
    # its iTunes parser. The <rss> shell check keeps an Atom feed with a
    # stray itunes attribute out — Feedjira parses those as Atom.
    ITUNES_NS = %r{xmlns:itunes\s?=\s?["']http://www\.itunes\.com/dtds/podcast-1\.0\.dtd["']}i
    CDATA = /<!\[CDATA\[.*?\]\]>/m

    def match?
      return false if fetched_body.blank?
      return false unless fetched_body.match?(/<rss[\s>]/i)

      fetched_body.gsub(CDATA, "").match?(ITUNES_NS)
    end
  end
end
