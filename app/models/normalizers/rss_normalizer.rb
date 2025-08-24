module Normalizers
  class RssNormalizer < Base
    def normalize
      # Placeholder for RSS normalization logic
      # This would convert processed items to a standard format
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
      # Basic HTML cleaning - in real implementation would use Sanitize gem
      text&.gsub(/<[^>]*>/, "")&.strip
    end
  end
end
