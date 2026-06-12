module Normalizer
  class AerostatNormalizer < RssNormalizer
    private

    def normalize_content
      title = raw_data.dig("title").to_s.strip
      enclosure_url = raw_data.dig("enclosure_url").presence
      enclosure_url ? "#{title}\nЗапись: #{enclosure_url}" : title
    end

    def normalize_attachment_urls
      [raw_data.dig("itunes_image")].compact_blank
    end

    def normalize_comments
      summary = raw_data.dig("summary").presence
      return [] unless summary

      stripped = strip_html(summary)
      [truncate_text(stripped, max_length: 1500)].compact_blank
    end
  end
end
