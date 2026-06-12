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
      @strip_images ||= story_pages.filter_map do |url, page|
        img = page.at_css("img#strip")
        if img.nil?
          Rails.error.report(
            StandardError.new("oglaf: page #{url} fetched but img#strip missing — markup changed?"),
            context: { feed_id: feed_entry.feed&.id, entry_uid: feed_entry.uid }
          )
        end
        img
      end
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
        pages << [next_url, page]
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
      if response.success?
        response.body
      else
        Rails.logger.warn("oglaf: skipping page #{url} for entry #{feed_entry.uid} (feed #{feed_entry.feed&.id}) — HTTP #{response.status}")
        nil
      end
    rescue HttpClient::Error => e
      Rails.logger.warn("oglaf: skipping page #{url} for entry #{feed_entry.uid} (feed #{feed_entry.feed&.id}) — #{e.message}")
      nil
    end
  end
end
