module Reddit
  # Reads public vote stats for a Reddit post without an API key, OAuth, or
  # registration.
  #
  # Reddit exposes a JSON view of any page by appending ".json" to its URL.
  # A single post URL returns a two-element array — [post_listing,
  # comments_listing] — and a subreddit/listing URL returns one listing object.
  # Either way the post data lives under data.children[].data, which carries the
  # vote fields the RSS feed omits (score, ups, upvote_ratio, num_comments).
  #
  # Two caveats shape any use of this data:
  # - Counts are intentionally "fuzzed" by Reddit, so treat them as approximate.
  # - Reddit serves 403 to unauthenticated requests from datacenter IPs, so
  #   whether this works at all depends on the egress IP. The retrieval probe
  #   (RedditRetrievalProbeJob) exists to answer that question per environment.
  class VotesFetcher
    USER_AGENT = "feeder-reddit-votes/0.1 (https://github.com/dreikanter/f2)".freeze

    class Error < StandardError; end

    # Raised for a non-2xx response; carries the numeric status so callers
    # (notably the probe) can record it as evidence.
    class HttpError < Error
      attr_reader :status

      def initialize(status)
        @status = status
        super("HTTP #{status}")
      end
    end

    Stats = Data.define(:id, :title, :author, :score, :ups, :upvote_ratio, :num_comments, :permalink) do
      def to_s
        "[#{score} pts | #{(upvote_ratio.to_f * 100).round}% up | #{num_comments} comments] #{title}"
      end
    end

    def initialize(http_client: HttpClient.build)
      @http_client = http_client
    end

    # Stats for a single post given its URL or permalink.
    def post(url)
      payload = get_json(json_url(url))
      child = children(payload.is_a?(Array) ? payload.first : payload).first
      raise Error, "No post found at #{url}" unless child

      build_stats(child)
    end

    # Stats for every post in a subreddit/user listing (e.g. r/ruby/top).
    def listing(url)
      children(get_json(json_url(url))).map { |child| build_stats(child) }
    end

    private

    attr_reader :http_client

    def json_url(url)
      base = url.to_s.strip.sub(/[#?].*\z/, "").chomp("/")
      base.end_with?(".json") ? base : "#{base}.json"
    end

    def get_json(url)
      response = http_client.get(url, headers: { "User-Agent" => USER_AGENT, "Accept" => "application/json" })
      raise HttpError, response.status unless response.success?

      JSON.parse(response.body)
    rescue HttpClient::Error => e
      raise Error, e.message
    rescue JSON::ParserError => e
      raise Error, "Invalid JSON: #{e.message}"
    end

    def children(listing)
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
