module ProfileMatcher
  class JsonFeedProfileMatcher < Base
    input_shape :url
    # Ranks above generic RSS (10): parsing and validating the JSON Feed
    # structure is a stronger signal than the RSS matcher's regex scan for
    # XML-like text, which a JSON feed can trip on if an item's HTML body
    # contains a `<feed>` or `<rss>` substring.
    match_specificity 20

    def match?
      return false if fetched_body.blank?

      JsonFeed.feed?(parse(fetched_body))
    end

    private

    def parse(body)
      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end
  end
end
