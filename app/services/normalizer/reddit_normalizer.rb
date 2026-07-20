module Normalizer
  # Reddit-specific normalizer that extracts the post body from the HTML
  # description field, separating it from Reddit's "submitted by" footer.
  # Link posts (no body) fall back to title only.
  class RedditNormalizer < RssNormalizer
    private

    # Reddit HTML-escapes titles inside the feed XML, so character references
    # like &#8217; survive the XML parse and need one more decode pass.
    def normalize_content
      title = strip_html(raw_data.dig("title"))
      body = extract_post_body
      body.present? ? "#{title}\n\n#{body}" : title
    end

    # Reddit's RSS only exposes images through its preview CDN
    # (*.redd.it), which serves a block page with HTTP 403 to non-browser
    # clients. There's no reliable way to download these, so we skip image
    # attachments for Reddit posts entirely. The permalink in the content
    # still links back to the original post with its media.
    def normalize_attachment_urls
      []
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
