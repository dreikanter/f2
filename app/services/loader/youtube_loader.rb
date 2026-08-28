module Loader
  class YoutubeLoader < Base
    FEED_URL_PATH = "/feeds/videos.xml"
    FEED_BASE_URL = "https://www.youtube.com/feeds/videos.xml"
    YOUTUBE_DOMAINS = %w[youtube.com www.youtube.com].freeze
    DEFAULT_MAX_REDIRECTS = 3

    CHANNEL_ID_PREFIX = "UC"

    # YouTube derives per-channel auto-playlists from the channel id. The UULF
    # one holds regular uploads with Shorts left out, and the keyless feed
    # serves it by playlist id.
    LONG_FORM_PLAYLIST_PREFIX = "UULF"

    def load
      response = http_client.get(feed_url)
      raise Loader::Error, "HTTP #{response.status}" unless response.success?
      response.body
    rescue HttpClient::Error => e
      raise Loader::Error, e.message
    end

    private

    def feed_url
      @feed_url ||= resolve_feed_url(feed.url)
    end

    def resolve_feed_url(url)
      resolved = if youtube_feed_url?(url)
        url
      else
        feed_url_from_url_pattern(url) || fetch_feed_url_from_html(url)
      end

      exclude_shorts? ? long_form_feed_url(resolved) : resolved
    end

    # Only a channel feed can be swapped for its long-form playlist; a feed
    # already pointing at a playlist or a legacy user is left as it is.
    def long_form_feed_url(url)
      channel_id = URI.decode_www_form(URI.parse(url).query.to_s).to_h["channel_id"]
      return url unless channel_id&.start_with?(CHANNEL_ID_PREFIX)

      playlist_id = channel_id.sub(CHANNEL_ID_PREFIX, LONG_FORM_PLAYLIST_PREFIX)
      "#{FEED_BASE_URL}?playlist_id=#{playlist_id}"
    rescue URI::InvalidURIError
      url
    end

    def exclude_shorts?
      feed.params&.dig("exclude_shorts")
    end

    def feed_url_from_url_pattern(url)
      uri = URI.parse(url)
      return nil unless youtube_domain?(uri.host)

      case uri.path
      when %r{\A/channel/([\w-]+)\z}
        "#{FEED_BASE_URL}?channel_id=#{$1}"
      when %r{\A/user/([\w.-]+)\z}
        "#{FEED_BASE_URL}?user=#{$1}"
      when "/playlist"
        params = URI.decode_www_form(uri.query.to_s).to_h
        playlist_id = params["list"]
        "#{FEED_BASE_URL}?playlist_id=#{playlist_id}" if playlist_id.present?
      end
    rescue URI::InvalidURIError
      nil
    end

    def fetch_feed_url_from_html(url)
      response = http_client.get(url)
      raise Loader::Error, "HTTP #{response.status}" unless response.success?

      extract_feed_url(response.body) or raise Loader::Error, "Could not find YouTube RSS feed link"
    end

    def youtube_domain?(host)
      YOUTUBE_DOMAINS.include?(host)
    end

    def youtube_feed_url?(url)
      URI.parse(url).path.start_with?(FEED_URL_PATH)
    rescue URI::InvalidURIError
      false
    end

    def extract_feed_url(html)
      doc = Nokogiri::HTML(html)
      link = doc.at_css('link[type="application/rss+xml"]') ||
             doc.at_css('link[type="application/atom+xml"]')
      link&.[]("href")
    end

    def http_client
      @http_client ||= options.fetch(:http_client) do
        max_redirects = options.fetch(:max_redirects, DEFAULT_MAX_REDIRECTS)
        HttpClient.build(max_redirects: max_redirects)
      end
    end
  end
end
