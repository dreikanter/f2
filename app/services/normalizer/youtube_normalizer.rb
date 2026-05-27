module Normalizer
  class YoutubeNormalizer < RssNormalizer
    private

    def normalize_content
      raw_data.dig("title") || ""
    end

    def normalize_attachment_urls
      thumbnail = raw_data.dig("thumbnail")
      thumbnail.present? ? [thumbnail] : []
    end

    def normalize_comments
      description = raw_data.dig("content") || ""
      description.present? ? [strip_html(description)] : []
    end
  end
end
