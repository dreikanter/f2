module TitleExtractor
  # Suggests a feed title for a Telegram channel. Prefers the channel's
  # display name from the fetched page's og:title, falling back to the
  # username from the input.
  class TelegramTitleExtractor < Base
    CHANNEL_URL = [%r{\A(?:www\.)?t\.me/}i, %r{\Atelegram\.me/}i, %r{\As/}i].freeze

    def title
      og_title.presence || account_name(*CHANNEL_URL).presence
    end
  end
end
