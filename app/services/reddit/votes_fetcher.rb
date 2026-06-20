module Reddit
  # PoC: read public vote stats for a Reddit post without an API key, OAuth,
  # or registration.
  #
  # Reddit exposes a JSON view of any page by appending ".json" to its URL.
  # A single post URL returns a two-element array — [post_listing,
  # comments_listing] — and a subreddit/listing URL returns one listing object.
  # Either way the post data lives under data.children[].data, which carries the
  # vote fields the RSS feed omits (score, ups, upvote_ratio, num_comments).
  #
  # Caveats worth remembering:
  # - Counts are intentionally "fuzzed" by Reddit, so treat them as approximate.
  # - Reddit blocks unauthenticated requests from datacenter IPs, so a real
  #   deployment needs a descriptive User-Agent and likely residential egress.
  class VotesFetcher
    USER_AGENT = "feeder-reddit-votes-poc/0.1 (https://github.com/dreikanter/f2)".freeze

    class Error < StandardError; end

    Stats = Data.define(:id, :title, :author, :score, :ups, :upvote_ratio, :num_comments, :permalink) do
      def to_s
        "[#{score} pts | #{(upvote_ratio * 100).round}% up | #{num_comments} comments] #{title}"
      end
    end

    def initialize(http_client: HttpClient.build)
      @http_client = http_client
    end

    # Stats for a single post given its URL or permalink.
    def post(url)
      payload = get_json(json_url(url))
      child = listing_children(payload.is_a?(Array) ? payload.first : payload).first
      raise Error, "No post found at #{url}" unless child

      build_stats(child)
    end

    # Stats for every post in a subreddit/user listing (e.g. r/ruby/top).
    def listing(url)
      payload = get_json(json_url(url))
      listing_children(payload).map { |child| build_stats(child) }
    end

    private

    attr_reader :http_client

    def json_url(url)
      base = url.to_s.strip.sub(/[#?].*\z/, "").chomp("/")
      base.end_with?(".json") ? url.to_s.strip : "#{base}.json"
    end

    def get_json(url)
      response = http_client.get(url, headers: { "User-Agent" => USER_AGENT, "Accept" => "application/json" })
      raise Error, "HTTP #{response.status}" unless response.success?

      JSON.parse(response.body)
    rescue HttpClient::Error => e
      raise Error, e.message
    rescue JSON::ParserError => e
      raise Error, "Invalid JSON: #{e.message}"
    end

    def listing_children(listing)
      listing.dig("data", "children") || []
    end

    def build_stats(child)
      data = child.fetch("data")

      Stats.new(
        id: data["id"],
        title: data["title"],
        author: data["author"],
        score: data["score"],
        ups: data["ups"],
        upvote_ratio: data["upvote_ratio"],
        num_comments: data["num_comments"],
        permalink: data["permalink"] && "https://www.reddit.com#{data['permalink']}"
      )
    end
  end
end
