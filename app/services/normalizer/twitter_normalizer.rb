module Normalizer
  # Maps a parsed tweet into a Post: the tweet text becomes the content (with
  # the tweet permalink appended, like the other profiles) and any photos or
  # video thumbnails become attachments.
  class TwitterNormalizer < RssNormalizer
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
