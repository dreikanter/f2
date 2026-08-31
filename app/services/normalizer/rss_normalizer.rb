module Normalizer
  # RSS-specific normalizer for feed entries
  class RssNormalizer < Base
    # Where an entry's text may live, best source first.
    CONTENT_FIELDS = %w[summary content description title].freeze

    private

    def content
      @content ||= post_content_with_url(text_content, source_url)
    end

    def text_content
      @text_content ||= normalize_content
    end

    def original_url
      @original_url ||= raw_data.dig("link") || raw_data.dig("url") || ""
    end

    def validate_content
      errors = super
      errors << "missing_url" if source_url.blank? || !valid_http_url?(source_url)
      errors << "url_too_long" if url_too_long?
      errors
    end

    def valid_http_url?(url)
      return false if url.blank?

      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    rescue URI::InvalidURIError
      false
    end

    def url_too_long?
      return false if original_url.blank?

      original_url.length > Post::MAX_URL_LENGTH
    end

    def normalize_source_url
      return "" if url_too_long?

      validate_url(original_url)
    end

    # An entry whose body is a bare image (comics, photo feeds) strips down to
    # nothing, so keep walking the chain instead of settling for the first
    # field that happens to be filled; the title is the last resort.
    def normalize_content
      CONTENT_FIELDS.lazy.filter_map { |field| strip_html(raw_data[field]).presence }.first || ""
    end

    def normalize_attachment_urls
      dedup_attachment_urls(image_urls + inline_images)
    end

    # The same image often arrives both as an <enclosure> and as an inline
    # <img>, differing only by a cache-busting query string (e.g. Beehiiv
    # appends `?t=123` to the in-content copy). Dedupe on the path so it
    # isn't attached twice; the first-seen URL wins.
    def dedup_attachment_urls(urls)
      urls.uniq { |url| url.split("?").first }
    end

    def image_urls
      enclosures = raw_data.dig("enclosures") || []
      enclosures.filter_map { |e| e["url"] if e["type"].nil? || e["type"].start_with?("image/") }
    end

    # Some feeds carry the post image only as an <img> inside <description>
    # (Feedjira's `summary`), with no enclosure and no content:encoded. Fall
    # back to it rather than scanning both fields: where a feed fills in
    # content:encoded, the excerpt tends to repeat the same picture as a
    # thumbnail under a different path, which would attach it twice.
    #
    # Images Base would drop as unsafe don't count as a hit, or a relative src
    # in content:encoded would mask a usable picture in the excerpt.
    def inline_images
      attachable_images(raw_data["content"]).presence || attachable_images(raw_data["summary"])
    end

    def attachable_images(html)
      extract_images(html).select { |url| PublicUrl.safe?(url) }
    end

    def validate_url(url)
      return "" if url.blank?

      URI.parse(url)
      url
    rescue URI::InvalidURIError
      ""
    end
  end
end
