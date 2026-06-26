module TitleExtractor
  # Extractor for JSON Feed titles (https://jsonfeed.org). The feed's
  # top-level `title` is required by the spec; fall back to the hostname
  # when the body is missing, unparseable, or titleless.
  class JsonFeedTitleExtractor < Base
    def title
      return hostname_from_url if fetched_body.blank?

      data = JSON.parse(fetched_body)
      feed_title = data.is_a?(Hash) ? data["title"].to_s.strip : ""
      feed_title.presence || hostname_from_url
    rescue JSON::ParserError
      hostname_from_url
    end
  end
end
