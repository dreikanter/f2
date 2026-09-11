module Normalizer
  class LitterboxNormalizer < RssNormalizer
    private

    def normalize_content
      title = raw_data["title"] || ""
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
        anchor.text.match?(/bonus panel/i) && bonus_panel_link?(anchor["href"])
      end
      link&.[]("href")
    end

    def bonus_panel_link?(url)
      return false unless PublicUrl.safe?(url)

      uri = URI.parse(url.strip)
      host = uri.hostname.downcase.chomp(".")
      return true unless host == "patreon.com" || host.end_with?(".patreon.com")

      uri.path.match?(%r{\A/(?:litterboxcomics/)?posts/(?:[^/]+-)?\d+/?\z})
    end

    def fetch_article_page
      @article_page ||= page_fetcher.fetch(source_url)
    end

    def bonus_panel_image_url
      page = page_fetcher.fetch(bonus_panel_url)
      return nil if page.nil?

      doc = Nokogiri::HTML(page)
      doc.at_css('meta[property="og:image"]')&.[]("content")
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
