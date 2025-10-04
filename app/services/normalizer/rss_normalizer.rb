module Normalizer
  # RSS-specific normalizer for feed entries
  class RssNormalizer < Base
    private

    def extract_post_attributes
      source_url = extract_source_url
      text_content = extract_content
      content = post_content_with_url(text_content, source_url)

      {
        source_url: source_url,
        content: content,
        attachment_urls: extract_attachment_urls,
        comments: extract_comments
      }
    end

    def validate_post(post)
      errors = super
      errors << "url_too_long" if url_too_long?(post)
      errors
    end

    def url_too_long?(post)
      return false if post.source_url.blank?

      post.source_url.length > Post::MAX_URL_LENGTH
    end

    def extract_source_url
      url = raw_data.dig("link") || raw_data.dig("url") || ""
      normalize_source_url(url)
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
