module Loader
  # Fetches a Bluesky author's timeline through the public AppView API
  # (public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed). It is documented,
  # needs no API key or login, and carries full-size image URLs — unlike the
  # profile's native RSS feed, which is text-only. Accepts a full bsky.app
  # profile URL identifying the account by handle or DID.
  class BlueskyLoader < Base
    API_URL = "https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed".freeze
    HOSTS = %w[bsky.app www.bsky.app].freeze
    # AT Protocol identifiers: a handle is a domain name (two labels minimum),
    # a DID is did:<method>:<identifier>.
    HANDLE = /\A[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)+\z/
    DID = /\Adid:[a-z]+:[a-zA-Z0-9._:%-]+\z/
    DEFAULT_MAX_REDIRECTS = 3

    def load
      identifier = actor
      unless identifier.match?(HANDLE) || identifier.match?(DID)
        raise Loader::Error, "Expected a bsky.app profile URL, got #{feed.url.inspect}"
      end

      response = http_client.get(feed_url(identifier), headers: { "Accept" => "application/json" })
      raise Loader::Error, error_message(response) unless response.success?

      response.body
    rescue HttpClient::Error => e
      raise Loader::Error, e.message
    end

    private

    # posts_no_replies keeps the timeline to top-level posts; reposts still
    # come through and are dropped by the processor.
    def feed_url(identifier)
      "#{API_URL}?#{URI.encode_www_form(actor: identifier, filter: "posts_no_replies")}"
    end

    # The account's handle or DID from a bsky.app/profile/<actor> URL. Only
    # the full URL form is accepted — bare handles are ambiguous (and the
    # params schema requires a URI anyway).
    def actor
      raw = feed.url.to_s.strip
      return "" unless raw.match?(%r{\Ahttps?://}i)

      path = raw.sub(%r{\Ahttps?://}i, "").split(/[?#]/).first.to_s
      segments = path.split("/").reject(&:empty?)
      return "" unless HOSTS.include?(segments.first.to_s.downcase)

      segments.second.to_s.casecmp?("profile") ? segments.third.to_s : ""
    end

    # The API answers errors with a JSON body whose message (e.g. "Profile
    # not found") is more useful than the bare status code.
    def error_message(response)
      detail = parsed_error(response.body)
      detail.present? ? "HTTP #{response.status}: #{detail}" : "HTTP #{response.status}"
    end

    def parsed_error(body)
      parsed = JSON.parse(body.to_s)
      parsed["message"] if parsed.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    def http_client
      @http_client ||= options.fetch(:http_client) do
        HttpClient.build(max_redirects: options.fetch(:max_redirects, DEFAULT_MAX_REDIRECTS))
      end
    end
  end
end
