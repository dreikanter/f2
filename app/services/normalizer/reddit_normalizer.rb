module Normalizer
  # Reddit-specific normalizer that extracts the post body from the HTML
  # description field, separating it from Reddit's "submitted by" footer.
  # Link posts (no body) fall back to title only.
  class RedditNormalizer < RssNormalizer
    private

    def normalize_content
      title = raw_data.dig("title").to_s.strip
      body = extract_post_body
      body.present? ? "#{title}\n\n#{body}" : title
    end

    def extract_post_body
      summary = raw_data.dig("summary") || ""
      return "" if summary.blank?

      doc = Nokogiri::HTML::DocumentFragment.parse(summary)
      md_div = doc.css("div.md").first
      return "" if md_div.nil?

      md_div.text.strip.gsub(/\s+/, " ")
    end
  end
end
