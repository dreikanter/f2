module Normalizer
  # Normalizer for push-ingested (webhook) feeds. The stored payload is the
  # validated webhook request body (spec 006 §3), so this maps its fields
  # straight onto Post, inheriting the Base choke-point guarantees: attachment
  # SSRF filtering, comment clamping, images_only, and the
  # no-content-no-images rule.
  class WebhookNormalizer < Base
    private

    def normalize_source_url
      raw_data["source_url"].presence
    end

    # House "link + commentary" shape: the source link folds into the body the
    # same way pull feeds compose it.
    def normalize_content
      post_content_with_url(raw_data["content"].to_s, normalize_source_url)
    end

    def normalize_attachment_urls
      Array(raw_data["images"]).map(&:to_s)
    end

    def normalize_comments
      Array(raw_data["comments"]).map(&:to_s)
    end

    # Spec 006 §3: content is required unless images is non-empty. Base's
    # default gate reads the composed content, where a bare source_url would
    # masquerade as content — check the raw payload field instead.
    def validate_content
      errors = []
      errors << "no_content_or_images" if raw_data["content"].to_s.blank? && attachment_urls.empty?
      errors.concat(images_only_errors)
      errors
    end
  end
end
