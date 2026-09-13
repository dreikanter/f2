module Normalizer
  class MonkeyuserNormalizer < RssNormalizer
    private

    def content
      return super if attachment_urls.any? || video_url.blank?

      @content ||= post_content_with_url(text_content, video_url)
    end

    def normalize_content
      title = raw_data["title"] || ""
      title.strip
    end

    def normalize_attachment_urls
      [comic_image_url].compact_blank
    end

    def normalize_comments
      hovertext = comic_image&.[]("title")
      [hovertext&.strip, (video_url if attachment_urls.any?)].compact_blank
    end

    def validate_content
      errors = super
      errors << "missing_images" if attachment_urls.empty? && video_url.blank?
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

      @comic_image = document.at_css(".comic img")
    end

    def video_url
      id = document.at_css(".comic .video-container > div[id]")&.[]("id")
      "https://www.youtube.com/watch?v=#{id}" if id&.match?(/\A[\w-]{11}\z/)
    end

    def document
      @document ||= Nokogiri::HTML(page.to_s)
    end

    def page_url
      raw_data["link"] || ""
    end

    def page
      return @page if defined?(@page)

      @page = page_fetcher.fetch(page_url)
    end
  end
end
