module Normalizer
  class TheycantalkNormalizer < RssNormalizer
    PROFILE_KEY = "theycantalk"

    private

    def normalize_content
      paragraphs.first || ""
    end

    def normalize_comments
      paragraphs[1..] || []
    end

    def normalize_attachment_urls
      summary = raw_data.dig("summary") || ""
      return [] if summary.blank?

      doc = Nokogiri::HTML::DocumentFragment.parse(summary)
      img = doc.css("img").first

      if img.nil?
        if doc.css("figure").any?
          Rails.logger.warn(
            "[#{PROFILE_KEY}] No <img> found inside <figure> — skipping attachment. " \
            "feed_id=#{feed_entry.feed&.id} uid=#{feed_entry.uid}"
          )
        end
        return []
      end

      src = img["src"].presence
      if src.nil?
        Rails.logger.warn(
          "[#{PROFILE_KEY}] <img> has blank src — skipping attachment. " \
          "feed_id=#{feed_entry.feed&.id} uid=#{feed_entry.uid}"
        )
        return []
      end

      [src]
    end

    def paragraphs
      @paragraphs ||= extract_paragraphs
    end

    def extract_paragraphs
      summary = raw_data.dig("summary") || ""
      return [] if summary.blank?

      doc = Nokogiri::HTML::DocumentFragment.parse(summary)

      doc.css("br, p, figure").each { |e| e.after("\n") }
      doc.css("img, figure").each(&:remove)

      doc.text.split("\n").map(&:strip).reject(&:blank?)
    end
  end
end
