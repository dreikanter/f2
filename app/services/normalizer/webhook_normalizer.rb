module Normalizer
  # Maps a stored webhook payload (spec 006 §3) onto a Post through the Base
  # choke-point guarantees: attachment SSRF filtering, comment clamping, and
  # the content rules.
  class WebhookNormalizer < Base
    private

    # Stripped to match the ingress service's reading of the field, so the
    # truncation-warning math and the stored link agree.
    def normalize_source_url
      raw_data["source_url"].to_s.strip.presence
    end

    # Folds the source link into the body, same shape as pull feeds.
    def normalize_content
      post_content_with_url(raw_data["content"].to_s, normalize_source_url)
    end

    def normalize_attachment_urls
      Array(raw_data["images"]).map(&:to_s)
    end

    def normalize_comments
      Array(raw_data["comments"]).map(&:to_s)
    end

    # Content is required unless images are present (spec 006 §3). Checked on
    # the raw payload field: in the composed content a bare source_url would
    # masquerade as content.
    def validate_content
      errors = []
      errors << "no_content_or_images" if raw_data["content"].to_s.blank? && attachment_urls.empty?
      errors.concat(images_only_errors)
      errors
    end
  end
end
