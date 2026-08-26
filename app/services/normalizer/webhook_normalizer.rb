module Normalizer
  # Maps a stored webhook payload onto a Post through the Base
  # choke-point guarantees: attachment SSRF filtering, comment clamping, and
  # the content rules.
  class WebhookNormalizer < Base
    private

    def payload
      @payload ||= WebhookPayload.new(raw_data)
    end

    def normalize_source_url = payload.source_url

    # Folds the source link into the body, same shape as pull feeds.
    def normalize_content
      post_content_with_url(payload.content, payload.source_url)
    end

    def normalize_attachment_urls = payload.images

    def normalize_comments = payload.comments

    # Content is required unless images are present. Checked on
    # the raw payload field: in the composed content a bare source_url would
    # masquerade as content.
    def validate_content
      errors = []
      errors << "no_content_or_images" if payload.content.blank? && attachment_urls.empty?
      errors.concat(images_only_errors)
      errors
    end
  end
end
