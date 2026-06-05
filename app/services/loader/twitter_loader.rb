module Loader
  # Fetches a public X/Twitter timeline through the syndication endpoint
  # (syndication.twitter.com/srv/timeline-profile/screen-name/<handle>) — the
  # same server-rendered feed that powers embeddable timelines. It needs no API
  # key or login and returns recent tweets as JSON inside the page.
  #
  # This is the most robust no-auth path available, but it is an unofficial
  # endpoint: it only exposes a short window of recent tweets, omits protected
  # accounts, and X may change or gate it at any time. Accepts a twitter.com /
  # x.com profile URL, an @handle, or a bare handle.
  class TwitterLoader < Base
    SYNDICATION_BASE = "https://syndication.twitter.com/srv/timeline-profile/screen-name".freeze
    HOSTS = %w[twitter.com www.twitter.com mobile.twitter.com x.com www.x.com].freeze
    HANDLE = /\A[A-Za-z0-9_]{1,15}\z/
    DEFAULT_MAX_REDIRECTS = 3

    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
                 "(KHTML, like Gecko) Chrome/124.0 Safari/537.36".freeze

    def load
      handle = screen_name
      raise StandardError, "Could not determine X/Twitter handle from #{feed.url.inspect}" unless handle.match?(HANDLE)

      response = http_client.get(
        "#{SYNDICATION_BASE}/#{handle}",
        headers: { "User-Agent" => USER_AGENT, "Accept" => "text/html" }
      )
      raise StandardError, "HTTP #{response.status}" unless response.success?

      response.body
    rescue HttpClient::Error => e
      raise StandardError, e.message
    end

    private

    def screen_name
      raw = feed.url.to_s.strip.sub(/\A@/, "").sub(%r{\Ahttps?://}i, "")
      parts = raw.split("/").reject(&:empty?)
      parts.shift if parts.first && HOSTS.include?(parts.first.downcase)
      parts.first.to_s
    end

    def http_client
      @http_client ||= options.fetch(:http_client) do
        HttpClient.build(max_redirects: options.fetch(:max_redirects, DEFAULT_MAX_REDIRECTS))
      end
    end
  end
end
