module Normalizer
  # Maps a parsed tweet into a Post: the tweet text becomes the content (with
  # the tweet permalink appended, like the other profiles) and any photos or
  # video thumbnails become attachments.
  class TwitterNormalizer < RssNormalizer
    include ProfilePayload

    private

    def normalize_content
      raw_data["text"].to_s
    end
  end
end
