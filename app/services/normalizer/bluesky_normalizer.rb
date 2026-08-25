module Normalizer
  # Maps a parsed Bluesky post into a Post: the post text becomes the content
  # with the bsky.app permalink appended, an external link card is folded into
  # the text, and any embedded images, gallery items, or video thumbnails
  # become attachments. The permalink is always constructed by the processor,
  # so unlike feed-sourced profiles no extra URL validation is needed beyond
  # the base checks.
  class BlueskyNormalizer < Base
    private

    def normalize_source_url
      raw_data["url"].to_s
    end

    def normalize_content
      post_content_with_url(text_with_link_card, source_url)
    end

    def normalize_attachment_urls
      Array(raw_data["images"]).uniq
    end

    def text_with_link_card
      [post_text, link_card_text].compact_blank.join("\n\n")
    end

    def post_text
      raw_data["text"].to_s
    end

    # Link cards usually come with little or no text of their own, so the
    # card's target is what the post is about. Bluesky also keeps the link in
    # the text when the author typed it there — no need to repeat it.
    def link_card_text
      card = raw_data["link_card"]
      return nil unless card.is_a?(Hash)

      url = card["url"].to_s
      return nil if url.blank? || post_text.include?(url)

      [card["title"].presence, url].compact.join("\n")
    end
  end
end
