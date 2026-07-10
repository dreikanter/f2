module Loader
  # Fetches a public Telegram channel's web preview at t.me/s/<channel>.
  #
  # Telegram renders recent channel posts — text and photos — as plain HTML
  # on this preview page, with no API key or login. We reuse it instead of
  # the MTProto API, which keeps the integration simple and free; the trade-off
  # is that channels without a public web preview (restricted content, groups,
  # private channels) cannot be loaded at all.
  #
  # Accepts the channel as a full URL (https://t.me/examplechannel,
  # https://t.me/s/examplechannel), a short form (t.me/examplechannel), an
  # @handle, or a bare username.
  class TelegramLoader < Base
    PREVIEW_BASE = "https://t.me/s".freeze
    HOSTS = %w[t.me telegram.me www.t.me].freeze
    USERNAME = /\A[A-Za-z0-9_]{2,64}\z/
    DEFAULT_MAX_REDIRECTS = 3

    # Container class of the message wall, present on every preview page (even
    # for channels with no posts yet). When a channel has no public preview,
    # t.me redirects to the plain info page, which lacks this container.
    PREVIEW_MARKER = "tgme_channel_history".freeze

    # t.me serves the lightweight preview markup to ordinary desktop browsers.
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
                 "(KHTML, like Gecko) Chrome/124.0 Safari/537.36".freeze

    def load
      name = channel_name
      raise Loader::Error, "Could not determine Telegram channel from #{feed.url.inspect}" unless name.match?(USERNAME)

      response = http_client.get("#{PREVIEW_BASE}/#{name}", headers: { "User-Agent" => USER_AGENT })
      raise Loader::Error, "HTTP #{response.status}" unless response.success?

      ensure_preview_page!(response.body, name)
      response.body
    rescue HttpClient::Error => e
      raise Loader::Error, e.message
    end

    private

    # A missing message wall means t.me silently served something other than
    # the preview — the info page of a preview-less channel, group, or user,
    # or telegram.org for an unclaimed name. Without this check such feeds
    # would look like valid channels that never post.
    def ensure_preview_page!(body, name)
      return if body.to_s.include?(PREVIEW_MARKER)

      raise Loader::Error,
            "No public web preview for #{name}: it may be restricted, private, or not a channel"
    end

    def channel_name
      raw = feed.url.to_s.strip.sub(/\A@/, "").sub(%r{\Ahttps?://}i, "")
      parts = raw.split("/").reject(&:empty?)
      parts.shift if parts.first && HOSTS.include?(parts.first.downcase)
      parts.shift if parts.first&.casecmp?("s")
      parts.first.to_s
    end

    def http_client
      @http_client ||= options.fetch(:http_client) do
        HttpClient.build(max_redirects: options.fetch(:max_redirects, DEFAULT_MAX_REDIRECTS))
      end
    end
  end
end
