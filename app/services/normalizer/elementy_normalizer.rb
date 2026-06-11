module Normalizer
  class ElementyNormalizer < RssNormalizer
    BASE_URL = "https://elementy.ru"

    private

    def normalize_content
      title = raw_data.dig("title") || ""
      title.strip
    end

    def normalize_comments
      summary = raw_data.dig("summary") || ""
      text = strip_html(summary)
      return [] if text.blank?

      [truncate_text(text, max_length: 1500)]
    end

    def normalize_attachment_urls
      page = fetch_page(raw_data.dig("link"))
      return [] if page.nil?

      doc = Nokogiri::HTML(page)
      img = doc.css(".ill_block img").first
      return [] if img.nil?

      src = img["src"]
      return [] if src.blank?

      [URI.join(BASE_URL, src).to_s]
    rescue URI::InvalidURIError
      []
    end

    def fetch_page(url)
      return nil if url.blank?

      response = HttpClient.build.get(url)
      return nil unless response.success?

      response.body
    rescue HttpClient::Error
      nil
    end
  end
end
