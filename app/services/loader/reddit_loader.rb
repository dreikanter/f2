module Loader
  # Fetches a Reddit RSS feed, normalising any form of Reddit input
  # (full URL, short name like "r/worldnews") to a /new.rss URL so that
  # entries arrive in chronological order regardless of what the user typed.
  class RedditLoader < HttpLoader
    SHORT_SUBREDDIT = %r{\Ar/([A-Za-z0-9_]+)\z}i
    SHORT_USER      = %r{\Auser/([A-Za-z0-9_-]+)\z}i
    REDDIT_PATH     = %r{reddit\.com/(r|user)/([A-Za-z0-9_-]+)}

    def load
      response = http_client.get(rss_url)
      raise StandardError, "HTTP #{response.status}" unless response.success?

      response.body
    rescue HttpClient::Error => e
      raise StandardError, e.message
    end

    private

    def rss_url
      @rss_url ||= build_rss_url(feed.url.to_s.strip)
    end

    def build_rss_url(input)
      if (m = input.match(SHORT_SUBREDDIT))
        "https://www.reddit.com/r/#{m[1]}/new.rss"
      elsif (m = input.match(SHORT_USER))
        "https://www.reddit.com/user/#{m[1]}/new.rss"
      elsif (m = input.match(REDDIT_PATH))
        "https://www.reddit.com/#{m[1]}/#{m[2]}/new.rss"
      else
        input
      end
    end
  end
end
