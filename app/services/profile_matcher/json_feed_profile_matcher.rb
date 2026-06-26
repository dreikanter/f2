module ProfileMatcher
  class JsonFeedProfileMatcher < Base
    input_shape :url
    match_specificity 10

    # https://jsonfeed.org/version/1.1 — a feed is a JSON object whose
    # `version` names the spec and which carries the required `title`
    # (string) and `items` (array) fields. Parsing and checking that
    # structure rules out HTML pages that merely link to the spec or
    # unrelated JSON that happens to mention the URL. Parsing also
    # normalizes any `\/`-escaped slashes, so the marker is matched
    # against the decoded value.
    VERSION_MARKER = "jsonfeed.org/version/".freeze

    def match?
      return false if fetched_body.blank?

      feed = parse(fetched_body)
      return false unless feed.is_a?(Hash)

      version = feed["version"]
      version.is_a?(String) && version.include?(VERSION_MARKER) &&
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
