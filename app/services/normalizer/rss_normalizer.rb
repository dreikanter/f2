module Normalizer
  # RSS-specific normalizer for feed entries
  class RssNormalizer < Base
    private

    def extract_source_url(raw_data)
      url = raw_data.dig("link") || raw_data.dig("url") || ""
      normalize_source_url(url)
    end

    def extract_content(raw_data)
      content = raw_data.dig("summary") || raw_data.dig("content") || raw_data.dig("description") || raw_data.dig("title") || ""
      result = strip_html(content)
      return "" if result.empty?

      truncate_content(result)
    end

    def extract_attachment_urls(raw_data)
      (image_urls(raw_data) + content_images(raw_data)).uniq
    end

    def image_urls(raw_data)
      enclosures = raw_data.dig("enclosures") || []
      enclosures.filter_map { |e| e["url"] if e["type"]&.start_with?("image/") }
    end

    def content_images(raw_data)
      extract_images_from_content(raw_data.dig("content") || "")
    end

    def extract_comments(raw_data)
      []
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
