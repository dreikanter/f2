module Normalizer
  class XkcdNormalizer < RssNormalizer
    private

    def normalize_content
      title = raw_data.dig("title") || ""
      title.strip
    end

    def normalize_comments
      alt_text = main_image&.[]("title")

      alt_text.present? ? [alt_text.strip] : []
    end

    def normalize_attachment_urls
      main_image&.[]("src") ? [main_image["src"]] : []
    end

    def main_image
      return @main_image if defined?(@main_image)

      summary = raw_data["summary"].to_s
      @main_image = summary.blank? ? nil : Nokogiri::HTML::DocumentFragment.parse(summary).at_css("img")
    end
  end
end
