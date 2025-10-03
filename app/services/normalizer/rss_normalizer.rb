module Normalizer
  # RSS-specific normalizer for feed entries
  class RssNormalizer < Base
    private

    def build_post
      post = super
      post.published_at = normalize_published_at(post.published_at)
      post
    end

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

      errors << "invalid_source_url" if source_url_invalid?(post)

      errors
    end

    def source_url_invalid?(post)
      post.source_url.blank? || !valid_url?(post.source_url)
    end

    def normalize_published_at(published_at)
      return Time.current if published_at > Time.current
      published_at
    end

    def extract_source_url(raw_data)
      raw_data.dig("link") || raw_data.dig("url") || ""
    end

    def extract_content(raw_data)
      content = raw_data.dig("summary") || raw_data.dig("content") || raw_data.dig("description") || raw_data.dig("title") || ""
      result = clean_html(content)
      return "" if result.empty?

      truncate_content(result)
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
      comments = []
      comments.map { |comment| truncate_comment(comment) }
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

    def truncate_content(content)
      return content if content.length <= Post::MAX_CONTENT_LENGTH

      # Use Rails truncate helper with word boundary preservation
      ActionController::Base.helpers.truncate(content, length: Post::MAX_CONTENT_LENGTH, separator: " ")
    end

    def truncate_comment(comment)
      return comment if comment.length <= Post::MAX_COMMENT_LENGTH

      ActionController::Base.helpers.truncate(comment, length: Post::MAX_COMMENT_LENGTH, separator: " ")
    end
  end
end
