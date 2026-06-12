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
      url = raw_data.dig("link")
      page = fetch_page(url)
      return [] if page.nil?

      doc = Nokogiri::HTML(page)
      img = doc.css(".ill_block img").first

      if img.nil?
        Rails.error.report(
          StandardError.new("elementy: page #{url} fetched but .ill_block img missing — markup changed?"),
          context: { profile: "elementy", feed_id: feed_entry.feed&.id, uid: feed_entry.uid, url: url }
        )
        return []
      end

      src = img["src"]
      return [] if src.blank?

      [URI.join(BASE_URL, src).to_s]
    rescue URI::InvalidURIError
      Rails.logger.warn(
        "elementy: skipping cover image — malformed img src #{src.inspect} on #{url} " \
        "(feed_id=#{feed_entry.feed&.id}, uid=#{feed_entry.uid})"
      )
      []
    end

    def fetch_page(url)
      return nil if url.blank?

      response = HttpClient.build.get(url)

      unless response.success?
        Rails.logger.warn(
          "elementy: skipping cover image — HTTP #{response.status} fetching #{url} " \
          "(feed_id=#{feed_entry.feed&.id}, uid=#{feed_entry.uid})"
        )
        return nil
      end

      response.body
    rescue HttpClient::Error => e
      Rails.logger.warn(
        "elementy: skipping cover image — #{e.class}: #{e.message} fetching #{url} " \
        "(feed_id=#{feed_entry.feed&.id}, uid=#{feed_entry.uid})"
      )
      nil
    end
  end
end
