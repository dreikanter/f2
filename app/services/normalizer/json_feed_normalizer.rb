module Normalizer
  # JSON Feed shares RSS's URL and image handling; only the text source
  # differs. RSS leads with `summary` because that's where RSS feeds put
  # the body, but JSON Feed's `summary` is an explicit short blurb and the
  # full item lives in `content` (content_html/content_text), so prefer it.
  class JsonFeedNormalizer < RssNormalizer
    private

    def normalize_content
      text = raw_data["content"].presence || raw_data["summary"].presence || raw_data["title"].presence || ""
      strip_html(text)
    end
  end
end
