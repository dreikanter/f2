module Normalizer
  class WordpressNormalizer < RssNormalizer
    private

    def normalize_content
      strip_html(raw_data["title"])
    end

    def normalize_comments
      [feed_text(raw_data["content"].presence || raw_data["summary"])].compact_blank
    end

    # WordPress plugins may advertise a separate sharing thumbnail as an
    # enclosure. The post body carries the actual panels and their order.
    def normalize_attachment_urls
      inline_images.presence || super
    end
  end
end
