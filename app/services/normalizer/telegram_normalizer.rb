module Normalizer
  # Maps a parsed Telegram message into a Post. The message text becomes the
  # content (with the t.me permalink appended, like the other profiles), and
  # channel photos / video thumbnails become attachments.
  class TelegramNormalizer < RssNormalizer
    private

    def normalize_content
      html = raw_data["text_html"].to_s
      return "" if html.blank?

      fragment = Nokogiri::HTML::DocumentFragment.parse(html)
      fragment.css("br").each { |br| br.replace("\n") }
      fragment.text.strip
    end

    def normalize_attachment_urls
      Array(raw_data["images"]).uniq
    end

    def original_url
      @original_url ||= raw_data["url"].to_s
    end
  end
end
