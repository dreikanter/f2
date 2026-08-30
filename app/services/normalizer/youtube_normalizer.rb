module Normalizer
  class YoutubeNormalizer < RssNormalizer
    private

    def normalize_content
      raw_data.dig("title") || ""
    end

    def normalize_attachment_urls
      # Freefeed renders the video preview from the source URL, so attaching
      # the thumbnail would just duplicate it.
      []
    end

    def normalize_comments
      return [] unless include_description?

      description = strip_html_preserving_paragraphs(raw_data.dig("content"))
      [description].compact_blank
    end

    def include_description?
      feed_entry.feed.params.fetch("include_description", true)
    end
  end
end
