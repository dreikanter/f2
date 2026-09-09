module Normalizer
  class LitterboxNormalizer < RssNormalizer
    private

    def normalize_content
      title = raw_data.dig("title") || ""
      title.strip
    end

    def normalize_attachment_urls
      return [] if bonus?

      page = fetch_article_page
      doc = Nokogiri::HTML(page || "")

      if doc.css(".swiper-wrapper").present?
        doc.css(".swiper-wrapper img").pluck("src").compact_blank.uniq
      else
        inline_images.uniq
      end
    end

    def normalize_comments
      return [] if bonus?

      url = bonus_panel_image_url || bonus_panel_link
      return [] if url.blank?

      ["Bonus panel: #{url}"]
    end

    def validate_content
      errors = super
      errors << "bonus" if bonus?
      errors
    end

    def bonus?
      URI.parse(source_url).path.to_s.match?(%r{-bonus/?\z})
    end

    def bonus_panel_link
      html = raw_data["content"].presence || raw_data["summary"] || ""
      link = Nokogiri::HTML::DocumentFragment.parse(html).css("a[href]").find do |anchor|
        anchor.text.match?(/bonus panel/i) && PublicUrl.safe?(anchor["href"])
      end
      link&.[]("href")
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

      URI.parse(link).tap do |uri|
        uri.path = "#{uri.path.sub(%r{/+\z}, '')}-bonus/"
      end.to_s
    end
  end
end
