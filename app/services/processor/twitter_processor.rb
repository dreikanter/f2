module Processor
  # Parses the X/Twitter syndication timeline into FeedEntry objects. The
  # endpoint returns a Next.js page whose `__NEXT_DATA__` script carries the
  # tweets as JSON under props.pageProps.timeline.entries[].content.tweet.
  class TwitterProcessor < Base
    TWITTER_FORMAT = "%a %b %d %H:%M:%S %z %Y".freeze

    def process
      timeline_tweets.filter_map { |tweet| build_entry(tweet) }
    end

    private

    def timeline_tweets
      script = Nokogiri::HTML.parse(raw_data, nil, "UTF-8").at_css("script#__NEXT_DATA__")
      return [] unless script

      data = JSON.parse(script.text)
      entries = data.dig("props", "pageProps", "timeline", "entries") || []
      entries.filter_map { |entry| entry.dig("content", "tweet") }
    rescue JSON::ParserError
      []
    end

    def build_entry(tweet)
      uid = tweet["id_str"].presence
      return nil unless uid

      published_at = parse_time(tweet["created_at"])
      return nil unless published_at

      FeedEntry.new(
        feed: feed,
        uid: uid,
        published_at: published_at,
        status: :pending,
        raw_data: {
          "uid" => uid,
          "url" => tweet_url(tweet),
          "text" => tweet_text(tweet),
          "images" => media_urls(tweet)
        }
      )
    end

    def tweet_url(tweet)
      permalink = tweet["permalink"].to_s
      return "https://twitter.com#{permalink}" if permalink.start_with?("/")

      permalink.presence || "https://twitter.com/i/web/status/#{tweet['id_str']}"
    end

    # Rebuilds readable text: expand t.co links to their targets, drop the
    # trailing t.co link that points to attached media, and decode the HTML
    # entities (&amp;, &lt;, &gt;) that the syndication API encodes.
    def tweet_text(tweet)
      text = tweet["full_text"].to_s
      Array(tweet.dig("entities", "urls")).each do |url|
        text = text.gsub(url["url"], url["expanded_url"]) if url["url"].present? && url["expanded_url"].present?
      end
      media(tweet).each { |item| text = text.gsub(item["url"], "") if item["url"].present? }
      CGI.unescapeHTML(text).strip
    end

    def media_urls(tweet)
      media(tweet).filter_map { |item| item["media_url_https"] || item["media_url"] }.uniq
    end

    def media(tweet)
      tweet.dig("extended_entities", "media") || tweet.dig("entities", "media") || []
    end

    def parse_time(value)
      return nil if value.blank?

      Time.strptime(value, TWITTER_FORMAT)
    rescue ArgumentError
      nil
    end
  end
end
