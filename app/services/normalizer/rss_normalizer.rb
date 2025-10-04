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

    # Keep original URL if it's a valid URI
    def normalize_source_url(url)
      return "" if url.blank?

      URI.parse(url)
      url
    rescue URI::InvalidURIError
      ""
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

    def clean_html(text)
      return "" if text.blank?

      doc = Nokogiri::HTML::DocumentFragment.parse(text)
      doc.text.strip.gsub(/\s+/, " ")
    end

    def extract_images_from_content(content)
      return [] if content.blank?

      doc = Nokogiri::HTML::DocumentFragment.parse(content)
      doc.css("img").map { |img| img["src"] }.compact
    end

    def truncate_content(content)
      return content if content.length <= Post::MAX_CONTENT_LENGTH

      content.truncate(Post::MAX_CONTENT_LENGTH, separator: " ")
    end

    def extract_comments(raw_data)
      []
    end
  end
end
