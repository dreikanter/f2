module Normalizer
  # RSS-specific normalizer for feed entries
  class RssNormalizer < Base
    private

    def content
      @content ||= post_content_with_url(text_content, source_url)
    end

    def text_content
      @text_content ||= extract_content
    end

    def original_url
      @original_url ||= raw_data.dig("link") || raw_data.dig("url") || ""
    end

    def validate_content
      errors = super
      errors << "url_too_long" if url_too_long?
      errors
    end

    def url_too_long?
      return false if original_url.blank?

      original_url.length > Post::MAX_URL_LENGTH
    end

    def extract_source_url
      return "" if url_too_long?

      normalize_source_url(original_url)
    end

    def extract_content
      content = raw_data.dig("summary") || raw_data.dig("content") || raw_data.dig("description") || raw_data.dig("title") || ""
      strip_html(content)
    end

    def extract_attachment_urls
      (image_urls + content_images).uniq
    end

    def image_urls
      enclosures = raw_data.dig("enclosures") || []
      enclosures.filter_map { |e| e["url"] if e["type"]&.start_with?("image/") }
    end

    def content_images
      extract_images(raw_data.dig("content") || "")
    end

    def normalize_source_url(url)
      return "" if url.blank?

      URI.parse(url)
      url
    rescue URI::InvalidURIError
      ""
    end
  end
end
