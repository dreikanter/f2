module Normalizer
  class XkcdNormalizer < RssNormalizer
    private

    def extract_content(raw_data)
      html_content = raw_data.dig("summary") || raw_data.dig("content") || raw_data.dig("description") || ""

      return "" if html_content.blank?

      doc = Nokogiri::HTML::DocumentFragment.parse(html_content)
      img_titles = doc.css("img").map { |img| img["title"] }.compact.reject(&:blank?)

      if img_titles.any?
        img_titles.first.strip
      else
        super(raw_data)
      end
    end

    def extract_attachment_urls(raw_data)
      enclosures = raw_data.dig("enclosures") || []
      image_urls = enclosures.filter_map { |e| e["url"] if e["type"]&.start_with?("image/") }

      summary_images = extract_images_from_content(raw_data.dig("summary") || "")
      content_images = extract_images_from_content(raw_data.dig("content") || "")

      all_images = (image_urls + summary_images + content_images).uniq
      all_images.empty? ? [] : [all_images.first]
    end
  end
end
