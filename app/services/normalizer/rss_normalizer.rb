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

    def validate_post(post)
      errors = []

      errors << "blank_content" if content_blank?(post)
      errors << "invalid_source_url" if source_url_invalid?(post)
      errors << "future_date" if published_in_future?(post)
      errors << "content_too_long" if content_too_long?(post)
      errors << "comment_too_long" if comment_too_long?(post)

      errors
    end

    def content_blank?(post)
      post.content.blank?
    end

    def source_url_invalid?(post)
      post.source_url.blank? || !valid_url?(post.source_url)
    end

    def published_in_future?(post)
      post.published_at > Time.current
    end

    def content_too_long?(post)
      post.content.length > Post::MAX_CONTENT_LENGTH
    end

    def comment_too_long?(post)
      post.comments.any? { |c| c.length > Post::MAX_COMMENT_LENGTH }
    end

    def extract_source_url(raw_data)
      raw_data.dig("link") || raw_data.dig("url") || ""
    end

    def extract_content(raw_data)
      content = raw_data.dig("summary") || raw_data.dig("content") || raw_data.dig("description") || raw_data.dig("title") || ""
      result = clean_html(content)
      result.empty? ? "" : result
    end

    def extract_attachment_urls(raw_data)
      enclosures = raw_data.dig("enclosures") || []
      image_urls = enclosures.select { |e| e["type"]&.start_with?("image/") }
                             .map { |e| e["url"] }
                             .compact

      content_images = extract_images_from_content(raw_data.dig("content") || "")

      (image_urls + content_images).uniq
    end

    def extract_comments(raw_data)
      []
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

    def valid_url?(url)
      uri = URI.parse(url)
      %w[http https].include?(uri.scheme)
    rescue URI::InvalidURIError
      false
    end
  end
end
