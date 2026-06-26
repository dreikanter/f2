module ProfileMatcher
  class JsonFeedProfileMatcher < Base
    input_shape :url
    match_specificity 10

    # A feed is a JSON object whose `version` is the spec URL (e.g.
    # "https://jsonfeed.org/version/1.1") and which carries the required
    # `title` (string) and `items` (array) fields. Parsing and checking
    # that structure rules out HTML pages that merely link to the spec or
    # unrelated JSON that happens to mention the URL; parsing also decodes
    # any `\/`-escaped slashes. The version is anchored to the canonical
    # host and path so a lookalike like `https://evil.com/jsonfeed.org/...`
    # or `https://notjsonfeed.org/version/1` can't slip through.
    VERSION_URL = %r{\Ahttps?://jsonfeed\.org/version/\d}

    def match?
      return false if fetched_body.blank?

      feed = parse(fetched_body)
      return false unless feed.is_a?(Hash)

      feed["version"].is_a?(String) && feed["version"].match?(VERSION_URL) &&
        feed["title"].is_a?(String) &&
        feed["items"].is_a?(Array)
    end

    private

    def parse(body)
      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end
  end
end
