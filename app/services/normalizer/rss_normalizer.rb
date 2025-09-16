module Normalizer
  class RssNormalizer < Base
    private

    def build_post
      raw_data = feed_entry.raw_data

      Post.new(
        feed: feed_entry.feed,
        feed_entry: feed_entry,
        uid: feed_entry.uid,
        published_at: feed_entry.published_at,
        link: extract_link(raw_data),
        text: extract_text(raw_data),
        attachment_urls: extract_attachment_urls(raw_data),
        comments: extract_comments(raw_data),
        status: :draft
      )
    end

    def validate_post(post)
      errors = []

      errors << "blank_text" if post.text.blank?
      errors << "invalid_link" if post.link.blank? || !valid_url?(post.link)
      errors << "future_date" if post.published_at > Time.current

      errors
    end

    def extract_link(raw_data)
      raw_data.dig("link") || raw_data.dig("url") || ""
    end

    def extract_text(raw_data)
      content = raw_data.dig("summary") || raw_data.dig("content") || raw_data.dig("title") || ""
      clean_html(content)
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
