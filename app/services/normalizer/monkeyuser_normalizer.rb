module Normalizer
  class MonkeyuserNormalizer < RssNormalizer
    private

    def normalize_content
      title = raw_data.dig("title") || ""
      title.strip
    end

    def normalize_attachment_urls
      [comic_image_url].compact_blank
    end

    def normalize_comments
      hovertext = comic_image&.[]("title")
      [hovertext&.strip].compact_blank
    end

    # A comic post without the comic itself is useless.
    def validate_content
      errors = super
      errors << "missing_images" if attachment_urls.empty?
      errors
    end

    def comic_image_url
      src = comic_image&.[]("src")
      return nil if src.blank?

      URI.join(page_url, src).to_s
    rescue URI::Error
      nil
    end

    def comic_image
      return @comic_image if defined?(@comic_image)

      @comic_image = page.presence && Nokogiri::HTML(page).css(".comic img").first
    end

    def page_url
      raw_data.dig("link") || ""
    end

    def page
      return @page if defined?(@page)

      @page = fetch_page(page_url)
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
