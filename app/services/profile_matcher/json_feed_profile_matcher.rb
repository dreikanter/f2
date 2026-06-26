module ProfileMatcher
  class JsonFeedProfileMatcher < Base
    input_shape :url
    match_specificity 10

    # Every JSON Feed names its spec version, e.g.
    # "https://jsonfeed.org/version/1.1". JSON may or may not escape the
    # slashes, so accept both forms. The textual check mirrors how the
    # RSS matcher sniffs for `<rss`/`<feed`; the processor's recognition
    # flag is the real gate.
    JSON_FEED_MARKERS = [
      "jsonfeed.org/version/",
      'jsonfeed.org\/version\/'
    ].freeze

    def match?
      return false if fetched_body.blank?

      JSON_FEED_MARKERS.any? { |marker| fetched_body.include?(marker) }
    end
  end
end
