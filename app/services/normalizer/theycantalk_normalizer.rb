module Normalizer
  class TheycantalkNormalizer < RssNormalizer
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
      img ? [img["src"]].compact : []
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
