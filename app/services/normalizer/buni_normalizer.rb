module Normalizer
  class BuniNormalizer < RssNormalizer
    WEBTOONS_DOMAIN = "webtoons.com"

    private

    def normalize_content
      image_title = comic_image&.[]("alt")
      image_title.presence || raw_data.dig("title") || ""
    end

    def normalize_attachment_urls
      image_url = comic_image&.[]("src")

      if image_url.blank? && page_fetched_ok?
        url = raw_data.dig("link")
        Rails.error.report(
          StandardError.new("buni: page #{url} fetched but comic image missing — markup changed?"),
          context: { feed_id: feed_entry.feed&.id, entry_uid: feed_entry.uid, entry_url: url }
        )
      end

      image_url.present? ? [image_url] : []
    end

    def normalize_comments
      return [] unless webtoons?

      ["Check out today's comic on Webtoons: #{first_link_url}"]
    end

    def validate_content
      errors = super
      errors << "missing_images" if attachment_urls.empty?
      errors
    end

    def comic_image
      return @comic_image if defined?(@comic_image)

      @comic_image = page.present? ? Nokogiri::HTML(page).css(image_selector).first : nil
    end

    # Some entries point at a Webtoons-hosted comic instead of an inline one;
    # those pages embed the image differently.
    def image_selector
      webtoons? ? ".entry img[srcset]" : "#comic img"
    end

    def page
      return @page if defined?(@page)

      url = raw_data.dig("link")
      @page = fetch_page(url)
    end

    # Returns true when the page fetch completed with an HTTP 2xx response,
    # regardless of whether a comic image was found in the body.
    def page_fetched_ok?
      @page_fetched_ok
    end

    def fetch_page(url)
      @page_fetched_ok = false
      return nil if url.blank?

      response = HttpClient.build.get(url)

      unless response.success?
        Rails.logger.warn(
          "buni: skipping comic image — HTTP #{response.status} fetching page " \
          "(feed_id=#{feed_entry.feed&.id} uid=#{feed_entry.uid} url=#{url})"
        )
        return nil
      end

      @page_fetched_ok = true
      response.body
    rescue HttpClient::Error => e
      Rails.logger.warn(
        "buni: skipping comic image — network error fetching page: #{e.message} " \
        "(feed_id=#{feed_entry.feed&.id} uid=#{feed_entry.uid} url=#{url})"
      )
      nil
    end

    def webtoons?
      return @webtoons if defined?(@webtoons)

      @webtoons = first_link_url.present? && webtoons_url?(first_link_url)
    end

    def webtoons_url?(url)
      host = URI.parse(url).host.to_s
      host == WEBTOONS_DOMAIN || host.end_with?(".#{WEBTOONS_DOMAIN}")
    rescue URI::InvalidURIError
      false
    end

    def first_link_url
      @first_link_url ||= begin
        html = raw_data.dig("content") || raw_data.dig("summary") || ""
        Nokogiri::HTML::DocumentFragment.parse(html).css("a").first&.[]("href").to_s
      end
    end
  end
end
