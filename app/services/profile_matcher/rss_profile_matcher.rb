module ProfileMatcher
  # Matcher for RSS/Atom feeds
  #
  # This is the default/fallback matcher that checks if the response
  # contains valid RSS or Atom XML.
  class RssProfileMatcher < Base
    RSS_INDICATORS = [
      /<rss[\s>]/i,
      /<feed[\s>]/i,
      /<rdf:RDF/i
    ].freeze

    # Determines if the feed is an RSS/Atom feed
    # @return [Boolean] true if the response contains RSS/Atom XML markers
    def match?
      return false if response.body.blank?

      RSS_INDICATORS.any? { |pattern| response.body.match?(pattern) }
    end
  end
end
