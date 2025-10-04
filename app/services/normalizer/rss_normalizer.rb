module Normalizer
  # RSS-specific normalizer for feed entries
  class RssNormalizer < Base
    private

    def extract_post_attributes(raw_data)
      source_url = extract_source_url(raw_data)
      text_content = extract_content(raw_data)
      content = post_content_with_url(text_content, source_url)

      @url_too_long = content.nil?

      {
        source_url: source_url,
        content: content || "",
        attachment_urls: extract_attachment_urls(raw_data),
        comments: extract_comments(raw_data)
      }
    end

    def validate_post(post)
      errors = super
      errors << "url_too_long" if @url_too_long
      errors
    end

    def extract_source_url(raw_data)
      url = raw_data.dig("link") || raw_data.dig("url") || ""
      normalize_source_url(url)
    end

    def extract_content(raw_data)
      content = raw_data.dig("summary") || raw_data.dig("content") || raw_data.dig("description") || raw_data.dig("title") || ""
      strip_html(content)
    end

    def extract_attachment_urls(raw_data)
      (image_urls(raw_data) + content_images(raw_data)).uniq
    end

    def image_urls(raw_data)
      enclosures = raw_data.dig("enclosures") || []
      enclosures.filter_map { |e| e["url"] if e["type"]&.start_with?("image/") }
    end

    def content_images(raw_data)
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
