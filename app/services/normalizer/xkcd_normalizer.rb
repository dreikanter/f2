module Normalizer
  class XkcdNormalizer < RssNormalizer
    private

    def extract_content
      title = raw_data.dig("title") || ""
      title.strip
    end

    def extract_comments
      summary = raw_data.dig("summary") || ""
      return [] if summary.blank?

      doc = Nokogiri::HTML::DocumentFragment.parse(summary)
      main_image = doc.css("img").first
      alt_text = main_image&.[]("title")

      alt_text.present? ? [alt_text.strip] : []
    end

    def extract_attachment_urls
      summary = raw_data.dig("summary") || ""
      return [] if summary.blank?

      doc = Nokogiri::HTML::DocumentFragment.parse(summary)
      main_image = doc.css("img").first

      main_image&.[]("src") ? [main_image["src"]] : []
    end
  end
end
