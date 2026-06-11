module Normalizer
  class SmbcNormalizer < RssNormalizer
    TITLE_PREFIX = /\ASaturday Morning Breakfast Cereal - /
    HOVERTEXT_PREFIX = /\AHovertext:\s*/

    private

    def normalize_content
      title = raw_data.dig("title") || ""
      title.sub(TITLE_PREFIX, "").strip
    end

    def normalize_comments
      [hovertext].compact_blank
    end

    def normalize_attachment_urls
      [comic_image_url, hidden_panel_image_url].compact_blank
    end

    def hovertext
      paragraph = summary_html.css("p").first
      return nil unless paragraph

      paragraph.text.sub(HOVERTEXT_PREFIX, "").strip
    end

    def comic_image_url
      summary_html.css("img").first&.[]("src")
    end

    def hidden_panel_image_url
      return nil if page.blank?

      Nokogiri::HTML(page).css("#aftercomic img").first&.[]("src")
    end

    def summary_html
      @summary_html ||= Nokogiri::HTML::DocumentFragment.parse(raw_data.dig("summary") || "")
    end

    def page
      return @page if defined?(@page)

      @page = fetch_page(raw_data.dig("link"))
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
