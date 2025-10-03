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
  end
end
