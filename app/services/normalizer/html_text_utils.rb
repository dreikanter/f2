module Normalizer
  module HtmlTextUtils
    def strip_html(text)
      return "" if text.blank?

      doc = Nokogiri::HTML::DocumentFragment.parse(text)
      doc.text.strip.gsub(/\s+/, " ")
    end

    def extract_images_from_content(content)
      return [] if content.blank?

      doc = Nokogiri::HTML::DocumentFragment.parse(content)
      doc.css("img").map { |img| img["src"] }.compact
    end

    def truncate_content(content, max_length: Post::MAX_CONTENT_LENGTH)
      return content if content.length <= max_length

      content.truncate(max_length, separator: " ")
    end
  end
end
