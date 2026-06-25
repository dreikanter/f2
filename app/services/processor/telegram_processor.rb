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
          "text_html" => wrap.at_css(".tgme_widget_message_text")&.inner_html.to_s,
          "images" => image_urls(wrap)
        }
      )
    end

    def message_url(wrap, uid)
      wrap.at_css(".tgme_widget_message_date")&.[]("href").presence || "https://t.me/#{uid}"
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
