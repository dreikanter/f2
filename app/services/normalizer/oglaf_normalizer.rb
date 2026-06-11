module Normalizer
  # Oglaf stories span one or more pages; the RSS entry only carries a
  # thumbnail, so the normalizer crawls the story pages via link[rel=next]
  # and collects the full-size strip image from each page.
  class OglafNormalizer < RssNormalizer
    SITE_URL = "https://www.oglaf.com"

    # Hard limit by Freefeed API
    MAX_PAGES = 20

    # In-story pagination links end with a page number (e.g. /goat/2/),
    # while the next link on the last page points at the next story.
    STORY_PAGE_PATTERN = %r{/\d+/$}

    private

    def normalize_content
      title = raw_data.dig("title") || ""
      title.strip
    end

    def normalize_attachment_urls
      strip_images.filter_map { |image| image["src"] }
    end

    def normalize_comments
      strip_images.filter_map { |image| image["title"]&.strip }.compact_blank
    end

    def strip_images
      @strip_images ||= story_pages.filter_map { |page| page.at_css("img#strip") }
    end

    def story_pages
      @story_pages ||= crawl_story_pages
    end

    def crawl_story_pages
      pages = []
      next_url = raw_data.dig("link")

      while next_url && pages.size < MAX_PAGES
        html = fetch_page(next_url)
        break if html.nil?

        page = Nokogiri::HTML(html)
        pages << page
        next_url = next_page_url(page)
      end

      pages
    end

    def next_page_url(page)
      href = page.at_css("link[rel=next]")&.[]("href")
      return nil if href.blank? || !href.match?(STORY_PAGE_PATTERN)

      URI.join(SITE_URL, href).to_s
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
