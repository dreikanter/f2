module Normalizer
  class TomorrowsNormalizer < RssNormalizer
    PROFILE_KEY = "tomorrows"

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
      url = raw_data.dig("link") || ""
      page = fetch_page(url)
      if page
        extract_story_from_page(page, url)
      else
        Rails.logger.warn(
          "tomorrows: page fetch failed for entry #{feed_entry.uid.inspect}, " \
          "feed_id=#{feed_entry.feed&.id}, url=#{url.inspect} — falling back to RSS summary"
        )
        fallback_story_text
      end
    end

    def extract_story_from_page(html, url)
      doc = Nokogiri::HTML(html)
      node = doc.css(".entry-content").first

      unless node
        Rails.error.report(
          StandardError.new("tomorrows: page #{url} fetched but .entry-content missing — markup changed?"),
          context: { profile: PROFILE_KEY, feed_id: feed_entry.feed&.id, uid: feed_entry.uid, url: url }
        )
        return nil
      end

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
