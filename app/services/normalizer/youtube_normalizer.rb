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
      description = raw_data.dig("content") || ""
      description.present? ? [strip_html(description)] : []
    end
  end
end
