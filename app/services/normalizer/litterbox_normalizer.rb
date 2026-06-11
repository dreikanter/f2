module Normalizer
  class LitterboxNormalizer < RssNormalizer
    private

    def normalize_content
      title = raw_data.dig("title") || ""
      title.strip
    end

    def normalize_attachment_urls
      page = fetch_article_page
      doc = Nokogiri::HTML(page || "")

      if doc.css(".swiper-wrapper").present?
        doc.css(".swiper-wrapper img").pluck("src").compact_blank
      else
        [extract_images(raw_data.dig("content") || "").first].compact
      end
    end

    def normalize_comments
      url = bonus_panel_image_url
      return [] if url.blank?

      ["Bonus panel: #{url}"]
    end

    def validate_content
      errors = super
      errors << "bonus" if bonus_post?
      errors
    end

    def fetch_article_page
      @article_page ||= begin
        response = HttpClient.build.get(source_url)
        response.success? ? response.body : nil
      rescue HttpClient::Error
        nil
      end
    end

    def bonus_panel_image_url
      bonus_url = bonus_panel_url
      return nil if bonus_url.blank?

      response = HttpClient.build.get(bonus_url)
      return nil unless response.success?

      doc = Nokogiri::HTML(response.body)
      doc.at_css('meta[property="og:image"]')&.[]("content")
    rescue HttpClient::Error
      nil
    end

    def bonus_panel_url
      link = source_url.to_s
      return nil if link.blank?

      base = link.sub(%r{/+\z}, "")
      "#{base}-bonus/"
    end

    def bonus_post?
      source_url.to_s.match?(%r{-bonus/?$})
    end
  end
end
