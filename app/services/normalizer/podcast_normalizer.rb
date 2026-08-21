module Normalizer
  class PodcastNormalizer < RssNormalizer
    private

    # Episode title as the post text with the audio link folded in; the
    # (often long) show notes travel as a comment instead.
    def normalize_content
      title = raw_data.dig("title").to_s.strip
      enclosure_url = raw_data.dig("enclosure_url").presence
      return title if enclosure_url.blank? || enclosure_url == source_url

      "#{title}\nListen: #{enclosure_url}"
    end

    # Some podcast feeds skip per-episode pages; the audio file is the only
    # stable URL then, so it stands in as the permalink.
    def original_url
      @original_url ||= super.presence || raw_data.dig("enclosure_url").to_s
    end

    def normalize_attachment_urls
      [raw_data.dig("itunes_image")].compact_blank
    end

    def normalize_comments
      summary = raw_data.dig("summary").presence
      return [] unless summary

      [truncate_text(strip_html(summary), max_length: 1500)].compact_blank
    end
  end
end
