module Normalizer
  class NextbigfutureNormalizer < RssNormalizer
    private

    def normalize_content
      title = raw_data.dig("title") || ""
      title.strip
    end

    def normalize_comments
      summary = raw_data.dig("summary") || ""
      return [] if summary.blank?

      text = strip_html(summary)
      return [] if text.blank?

      [truncate_text(text, max_length: 1500)]
    end

    def normalize_attachment_urls
      url = fetch_featured_image
      url ? [url] : []
    end

    def fetch_featured_image
      link = raw_data.dig("link") || raw_data.dig("url")
      return nil if link.blank?

      html = fetch_page(link)
      return nil if html.blank?

      doc = Nokogiri::HTML(html)
      img = doc.css(".featured-image img").first
      return nil unless img

      src = img["src"]
      return nil if src.blank?

      # Accept only absolute https URLs (guards against data: URIs)
      uri = URI.parse(src)
      uri.is_a?(URI::HTTPS) ? src : nil
    rescue URI::InvalidURIError
      nil
    end

    def fetch_page(url)
      response = HttpClient.build.get(url)
      return nil unless response.success?

      response.body
    rescue HttpClient::Error
      nil
    end
  end
end
