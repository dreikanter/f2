module Normalizer
  # XKCD-specific normalizer for RSS feeds
  # Extracts content from image title attributes which contain comic descriptions
  class XkcdNormalizer < RssNormalizer
    private

    # Override to extract content from image title attributes for XKCD comics
    # @param raw_data [Hash] RSS feed item data
    # @return [String] extracted content
    def extract_content(raw_data)
      # Try to get content from summary/content fields first
      html_content = raw_data.dig("summary") || raw_data.dig("content") || raw_data.dig("description") || ""

      return "" if html_content.blank?

      # Parse HTML to extract image title attributes
      doc = Nokogiri::HTML::DocumentFragment.parse(html_content)

      # Look for img tags with title attributes (XKCD comic descriptions)
      img_titles = doc.css("img").map { |img| img["title"] }.compact.reject(&:blank?)

      if img_titles.any?
        # Use the first image title as content (XKCD comics typically have one main image)
        img_titles.first.strip
      else
        # Fallback to regular text extraction if no image titles found
        super(raw_data)
      end
    end

    # Override to extract image URLs from summary field for XKCD comics
    # @param raw_data [Hash] RSS feed item data
    # @return [Array<String>] array of image URLs
    def extract_attachment_urls(raw_data)
      enclosures = raw_data.dig("enclosures") || []
      image_urls = enclosures.filter_map { |e| e["url"] if e["type"]&.start_with?("image/") }

      # Extract images from summary field (where XKCD stores comic images)
      summary_images = extract_images_from_content(raw_data.dig("summary") || "")
      content_images = extract_images_from_content(raw_data.dig("content") || "")

      (image_urls + summary_images + content_images).uniq
    end
  end
end
