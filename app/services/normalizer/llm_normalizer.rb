module Normalizer
  # Normalizer for AI-backed profiles. Two modes, selected by the
  # profile's normalizer config:
  #
  # * Passthrough (no `prompt_template`): the raw_data already has all
  #   universal-post fields; map them straight onto Post. Used by the `llm`
  #   profile, where the AI work happens at the loader stage.
  #
  # * LLM rewrite (`prompt_template` present in config): runs raw_data
  #   through `LlmClient` so a second prompt can clean up / translate /
  #   summarise the content before it lands in Post. Reserved for future
  #   rewrite profiles; the current `llm` profile doesn't use this branch.
  class LlmNormalizer < Base
    private

    def normalize_source_url
      raw_data["source_url"].to_s
    end

    def normalize_content
      truncate_text(raw_data["body"].to_s)
    end

    # Model-emitted image URLs are fetched server-side at publish time, so a
    # bad one is a §8 SSRF/local-file risk. Keep only public http(s) URLs and
    # drop the rest (drop the attachment, never the post).
    def normalize_attachment_urls
      Array(raw_data["images"]).map(&:to_s).select { |url| PublicUrl.safe?(url) }
    end

    def normalize_comments
      Array(raw_data["supplementary"]).map(&:to_s)
    end

    def normalize_published_at(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return Time.current if value.blank?

      Time.parse(value.to_s)
    rescue ArgumentError
      Time.current
    end

    def validate_content
      errors = []
      errors << "missing source_url" if normalize_source_url.blank?
      errors << "missing content" if normalize_content.blank?
      errors.concat(images_only_errors)
      errors
    end
  end
end
