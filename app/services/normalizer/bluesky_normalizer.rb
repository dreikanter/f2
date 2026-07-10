module Normalizer
  # Maps a parsed Bluesky post into a Post: the post text becomes the content
  # (with the bsky.app permalink appended, like the other profiles) and any
  # embedded images, gallery items, or video thumbnails become attachments.
  class BlueskyNormalizer < RssNormalizer
    private

    def normalize_content
      raw_data["text"].to_s
    end

    def normalize_attachment_urls
      Array(raw_data["images"]).uniq
    end

    def original_url
      @original_url ||= raw_data["url"].to_s
    end
  end
end
