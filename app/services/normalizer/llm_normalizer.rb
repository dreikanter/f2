module Normalizer
  # Maps AI extraction output in FeedProfile::UNIVERSAL_OUTPUT_SCHEMA format
  # onto Post fields, applying the feed pipeline's content validation.
  class LlmNormalizer < Base
    private

    # Preserve explicit nulls for Post's optional source URL validation.
    def normalize_source_url
      return nil if original?

      raw_data["source_url"].to_s
    end

    def original?
      raw_data.key?("source_url") && raw_data["source_url"].nil?
    end

    def normalize_content
      body = truncate_text(raw_data["body"].to_s)
      return body if body.blank? || source_url.blank?
      return body if body.match?(/#{Regexp.escape(source_url)}(?=$|[\s)\]>]|[.,;!?](?:\s|$))/)

      post_content_with_url(body, source_url)
    end

    # Base#attachment_urls filters non-public URLs at the choke point.
    def normalize_attachment_urls
      Array(raw_data["images"]).map(&:to_s)
    end

    def normalize_comments
      Array(raw_data["supplementary"]).map(&:to_s)
    end

    def validate_content
      errors = []
      errors << "missing_source_url" if source_url.blank? && !original?
      errors << "missing_content" if content.blank?
      errors.concat(images_only_errors)
      errors
    end
  end
end
