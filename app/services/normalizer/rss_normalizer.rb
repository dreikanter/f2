module Normalizer
  # RSS-specific normalizer for feed entries
  class RssNormalizer < Base
    private

    # Extracts RSS-specific content attributes
    # @param raw_data [Hash] RSS feed item data
    # @return [Hash] content attributes hash
    def extract_content_attributes(raw_data)
      {
        source_url: extract_source_url(raw_data),
        content: extract_content(raw_data),
        attachment_urls: extract_attachment_urls(raw_data),
        comments: extract_comments(raw_data)
      }
    end

    def extract_source_url(raw_data)
      url = raw_data.dig("link") || raw_data.dig("url") || ""
      normalize_source_url(url)
    end

    def extract_content(raw_data)
      content = raw_data.dig("summary") || raw_data.dig("content") || raw_data.dig("description") || raw_data.dig("title") || ""
      result = clean_html(content)
      return "" if result.empty?

      truncate_content(result)
    end

    def extract_attachment_urls(raw_data)
      (image_urls + content_images).uniq
    end

    def image_urls
      enclosures = raw_data.dig("enclosures") || []
      enclosures.filter_map { |e| e["url"] if e["type"]&.start_with?("image/") }
    end

    def content_images
      extract_images_from_content(raw_data.dig("content") || "")
    end

    def extract_comments(raw_data)
      []
    end
  end
end
