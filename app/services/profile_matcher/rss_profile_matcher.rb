module ProfileMatcher
  class RssProfileMatcher < Base
    RSS_INDICATORS = [
      /<rss[\s>]/i,
      /<feed[\s>]/i,
      /<rdf:RDF/i
    ].freeze

    def self.profile_key
      "rss"
    end

    def match?
      return false if response.body.blank?

      RSS_INDICATORS.any? { |pattern| response.body.match?(pattern) }
    end
  end
end
