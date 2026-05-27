module Loader
  class YoutubeLoader < Base
    FEED_URL_PATH = "/feeds/videos.xml"
    DEFAULT_MAX_REDIRECTS = 3

    def load
      response = http_client.get(feed_url)
      raise StandardError, "HTTP #{response.status}" unless response.success?
      response.body
    rescue HttpClient::Error => e
      raise StandardError, e.message
    end

    private

    def feed_url
      @feed_url ||= resolve_feed_url(feed.url)
    end

    def resolve_feed_url(url)
      return url if youtube_feed_url?(url)

      response = http_client.get(url)
      raise StandardError, "HTTP #{response.status}" unless response.success?

      extract_feed_url(response.body) or raise StandardError, "Could not find YouTube RSS feed link"
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
