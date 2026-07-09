module ProfileMatcher
  class RssProfileMatcher < Base
    match_specificity 10

    RSS_INDICATORS = [
      /<rss[\s>]/i,
      /<feed[\s>]/i,
      /<rdf:RDF/i
    ].freeze

    def match?
      return false if fetched_body.blank?

      RSS_INDICATORS.any? { |pattern| fetched_body.match?(pattern) }
    end
  end
end
