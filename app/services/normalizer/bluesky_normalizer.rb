module Normalizer
  # Maps a parsed Bluesky post into a Post: the post text becomes the content
  # with the bsky.app permalink appended, and any embedded images, gallery
  # items, or video thumbnails become attachments. The permalink is always
  # constructed by the processor, so unlike feed-sourced profiles no extra
  # URL validation is needed beyond the base checks.
  class BlueskyNormalizer < Base
    private

    def normalize_source_url
      raw_data["url"].to_s
    end

    def normalize_content
      post_content_with_url(raw_data["text"].to_s, source_url)
    end

    def normalize_attachment_urls
      Array(raw_data["images"]).uniq
    end
  end
end
