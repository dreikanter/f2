module Normalizer
  # Normalizer for the AI extraction profile. The AI work happens at the
  # loader stage, so raw_data already carries the universal-post fields
  # (FeedProfile::UNIVERSAL_OUTPUT_SCHEMA); this maps them straight onto
  # Post. No LLM call happens here.
  class LlmNormalizer < Base
    private

    # A digest item carries source_url = null end-to-end: keep it nil
    # (not "") so the nullable column stores NULL and Post's conditional
    # validation lets it publish. A feed-style item keeps its string permalink.
    def normalize_source_url
      return nil if digest?

      raw_data["source_url"].to_s
    end

    def digest?
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
      errors << "missing_source_url" if source_url.blank? && !digest?
      errors << "missing_content" if content.blank?
      errors.concat(images_only_errors)
      errors
    end
  end
end
