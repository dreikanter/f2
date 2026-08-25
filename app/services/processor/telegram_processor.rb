module Processor
  # Turns the t.me/s/<channel> HTML preview into one FeedEntry per message.
  #
  # Each message lives in a `.tgme_widget_message_wrap` block carrying a stable
  # `data-post` id ("channel/123"), a permalink, an ISO-8601 timestamp, optional
  # text, and photos/video thumbnails exposed as CSS `background-image` URLs.
  # Service messages without a `data-post` id are skipped.
  class TelegramProcessor < Base
    MESSAGE_SELECTOR = "div.tgme_widget_message_wrap".freeze
    IMAGE_SELECTOR = [
      ".tgme_widget_message_photo_wrap",
      ".tgme_widget_message_video_thumb",
      ".tgme_widget_message_roundvideo_thumb"
    ].join(", ").freeze
    BACKGROUND_IMAGE = /background-image:\s*url\(['"]?(.*?)['"]?\)/i

    # t.me escapes the ampersands of a link URL on top of the escaping the
    # surrounding HTML already gets — anchors carrying an onclick handler are
    # the usual offenders — so one decode leaves a literal "&amp;" sitting in
    # the query string. Left alone it travels into the post and breaks the
    # link. Repairing decoded values is a no-op for correctly escaped markup.
    ESCAPED_AMPERSAND = /&amp;/i

    def process
      entries = document.css(MESSAGE_SELECTOR).filter_map { |wrap| build_entry(wrap) }
      Result.new(entries: entries, recognized: true)
    end

    private

    def document
      Nokogiri::HTML.parse(raw_data, nil, "UTF-8")
    end

    def build_entry(wrap)
      message = wrap.at_css(".tgme_widget_message")
      uid = message&.[]("data-post").presence
      return nil unless uid

      # The publish-date <time datetime> sits inside the message footer; video
      # posts also carry a <time class="message_video_duration"> with no
      # datetime, so select the dated one explicitly rather than the first.
      published_at = parse_time(wrap.at_css("time[datetime]")&.[]("datetime"))
      return nil unless published_at

      FeedEntry.new(
        feed: feed,
        uid: uid,
        published_at: published_at,
        status: :pending,
        raw_data: {
          "uid" => uid,
          "url" => message_url(wrap, uid),
          "text_html" => text_html(wrap),
          "images" => image_urls(wrap)
        }
      )
    end

    def message_url(wrap, uid)
      href = wrap.at_css(".tgme_widget_message_date")&.[]("href").presence
      href ? unescape_ampersands(href) : "https://t.me/#{uid}"
    end

    def text_html(wrap)
      text = wrap.at_css(".tgme_widget_message_text")
      return "" unless text

      repair_link_urls(text)
      text.inner_html
    end

    # Repairs both the href and the URL t.me renders as the link's own text.
    # A caption is left as typed: a rendered URL never carries whitespace.
    def repair_link_urls(node)
      node.css("a[href]").each do |anchor|
        anchor["href"] = unescape_ampersands(anchor["href"])
        anchor.xpath(".//text()").each do |text|
          next if text.content.match?(/\s/)

          text.content = unescape_ampersands(text.content)
        end
      end
    end

    def unescape_ampersands(url)
      url.gsub(ESCAPED_AMPERSAND, "&")
    end

    def image_urls(wrap)
      wrap.css(IMAGE_SELECTOR).filter_map { |el| el["style"]&.[](BACKGROUND_IMAGE, 1) }.uniq
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value)
    rescue ArgumentError
      nil
    end
  end
end
