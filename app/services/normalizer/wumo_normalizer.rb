module Normalizer
  class WumoNormalizer < RssNormalizer
    private

    def normalize_content
      strip_html(raw_data["title"])
    end

    def normalize_attachment_urls
      [extract_images(raw_data["summary"]).first].compact_blank
    end

    def validate_content
      errors = super
      errors << "missing_images" if attachment_urls.empty?
      errors << "missing_publication_date" if feed_entry.published_at.nil?
      errors
    end
  end
end
