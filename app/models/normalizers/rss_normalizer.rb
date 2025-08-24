module Normalizers
  class RssNormalizer < Base
    def normalize
      # TBD
      processed_items.map do |item|
        {
          feed_id: feed.id,
          title: clean_html(item[:title]),
          content: clean_html(item[:content]),
          published_at: item[:published_at],
          source_url: item[:url],
          normalized_at: Time.current
        }
      end
    end

    private

    def clean_html(text)
      return text if text.blank?

      # Parse HTML safely and extract text content only
      doc = Nokogiri::HTML::DocumentFragment.parse(text)
      doc.text.strip
    end
  end
end
