module TitleExtractor
  # Suggests a feed title for a Telegram channel. Prefers the channel's
  # display name from the fetched page's og:title, falling back to the
  # username from the input.
  class TelegramTitleExtractor < Base
    def title
      og_title.presence || username.presence
    end

    private

    def og_title
      return nil if fetched_body.blank?

      doc = Nokogiri::HTML.parse(fetched_body, nil, "UTF-8")
      doc.at_css('meta[property="og:title"]')&.[]("content")&.strip
    rescue StandardError
      nil
    end

    def username
      input.to_s.strip.sub(/\A@/, "").sub(%r{\Ahttps?://}i, "")
           .sub(%r{\A(?:www\.)?t\.me/}i, "").sub(%r{\Atelegram\.me/}i, "")
           .sub(%r{\As/}i, "").split("/").first.to_s
    end
  end
end
