module Normalizer
  class TomorrowsNormalizer < RssNormalizer
    private

    def normalize_content
      title = raw_data.dig("title") || ""
      title.strip
    end

    def normalize_comments
      text = story_text
      return [] if text.blank?

      [truncate_text(text, max_length: 1500)]
    end

    def story_text
      page = fetch_page(raw_data.dig("link") || "")
      if page
        extract_story_from_page(page)
      else
        fallback_story_text
      end
    end

    def extract_story_from_page(html)
      doc = Nokogiri::HTML(html)
      node = doc.css(".entry-content").first
      return nil unless node

      paragraphs = node.css("p").map { |p| p.text.gsub(/[[:space:]]+/, " ").strip }
      paragraphs.reject(&:blank?).join("\n\n")
    end

    def fallback_story_text
      raw = raw_data.dig("content") || raw_data.dig("summary") || ""
      text = strip_html(raw)
      text.presence
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
