# Live probe for Reddit vote-data retrieval (companion to LlmCapabilityProbe).
#
# The open question for Reddit::VotesFetcher isn't the parsing — that's unit
# tested — but whether the ".json" endpoint is reachable at all from a given
# egress IP. Reddit serves 403 to unauthenticated requests from datacenter IPs,
# and the sandbox/CI environment is blocked, so this only gets a real answer
# when run from the deployed host via the dev-area jobs runner
# (RedditRetrievalProbeJob). Every check records its HTTP status and a sample of
# what came back as JobRun events, so the verdict — and the evidence behind it —
# survives without a transcript to chase.
#
# The checks are chosen to localize a failure, not just report one:
# - listing / single_post exercise the real fetcher against the JSON API.
# - old_reddit tests an alternate host, in case one is blocked and the other not.
# - rss_control fetches the RSS feed the app already uses; RSS 200 with JSON 403
#   means "JSON specifically is blocked", while both 403 means the IP is blocked
#   outright.
module RedditRetrievalProbe
  SUBREDDIT = "programming".freeze
  LISTING_URL = "https://www.reddit.com/r/#{SUBREDDIT}/top.json?t=week&limit=5".freeze
  OLD_LISTING_URL = "https://old.reddit.com/r/#{SUBREDDIT}/top.json?t=week&limit=5".freeze
  API_URL = "https://api.reddit.com/r/#{SUBREDDIT}/top?t=week&limit=5".freeze
  RSS_URL = "https://www.reddit.com/r/#{SUBREDDIT}/new.rss".freeze

  BROWSER_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " \
               "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze

  # Diagnostic matrix for the JSON 403: staging gets RSS 200 but .json 403 with
  # the same IP+UA, so each strategy isolates a candidate cause (the Accept
  # header, a datacenter-flagged UA, the host) to find an authless route or rule
  # one out. PASS if any strategy returns 200.
  JSON_STRATEGIES = [
    { label: "ua+accept-json", url: LISTING_URL, ua: Reddit::VotesFetcher::USER_AGENT, accept: "application/json" },
    { label: "ua-only",        url: LISTING_URL, ua: Reddit::VotesFetcher::USER_AGENT, accept: nil },
    { label: "browser-ua",     url: LISTING_URL, ua: BROWSER_UA, accept: nil },
    { label: "browser+rawjson", url: "#{LISTING_URL}&raw_json=1", ua: BROWSER_UA, accept: "application/json" },
    { label: "api.reddit.com", url: API_URL, ua: BROWSER_UA, accept: "application/json" }
  ].freeze

  def self.run(...) = Runner.new(...).run

  class Runner
    CHECKS = %w[listing single_post old_reddit rss_control strategies].freeze

    def initialize(fetcher: Reddit::VotesFetcher.new, http_client: HttpClient.build, checks: CHECKS)
      @fetcher = fetcher
      @http_client = http_client
      @checks = checks
      @results = []
      @first_permalink = nil
    end

    # Returns { results:, passed: }. Mirrors LlmCapabilityProbe::Runner: every
    # check is attempted, failures are recorded rather than raised.
    def run
      @checks.each { |check| record(check) { send("check_#{check}") } }
      { results: @results, passed: @results.none? { |r| r[:status] == "FAIL" } }
    end

    private

    def record(check)
      started = Time.current
      outcome = yield
      @results << outcome.merge(check: check, seconds: (Time.current - started).round(1))
    rescue StandardError => e
      @results << { check: check, status: "FAIL", note: "#{e.class}: #{e.message.to_s[0, 300]}",
                    evidence: nil, seconds: (Time.current - started).round(1) }
    end

    def check_listing
      posts = @fetcher.listing(LISTING_URL)
      scored = posts.select { |p| p.score.is_a?(Numeric) }
      @first_permalink = posts.first&.permalink
      evidence = scored.first(3).map(&:to_s)

      if scored.empty?
        { status: "FAIL", note: "no posts with a numeric score", evidence: posts.first(3).map(&:to_s) }
      else
        { status: "PASS", note: "#{scored.size} scored posts", evidence: evidence }
      end
    end

    def check_single_post
      return { status: "SKIP", note: "listing returned no permalink to follow", evidence: nil } if @first_permalink.blank?

      stats = @fetcher.post(@first_permalink)
      if stats.score.is_a?(Numeric)
        { status: "PASS", note: "score=#{stats.score}, comments=#{stats.num_comments}", evidence: stats.to_s }
      else
        { status: "FAIL", note: "post payload had no numeric score", evidence: stats.to_s }
      end
    end

    def check_old_reddit
      status = raw_status(OLD_LISTING_URL)
      pass = status == 200
      { status: pass ? "PASS" : "FAIL", note: "old.reddit.com/.json → HTTP #{status}", evidence: nil }
    end

    # RSS is the app's current Reddit route; a 200 here isolates the JSON block.
    def check_rss_control
      status = raw_status(RSS_URL)
      pass = status == 200
      { status: pass ? "PASS" : "FAIL", note: "new.rss → HTTP #{status}", evidence: nil }
    end

    # Tries each authless JSON strategy and reports its HTTP status as evidence.
    def check_strategies
      results = JSON_STRATEGIES.map do |strategy|
        headers = { "User-Agent" => strategy[:ua] }
        headers["Accept"] = strategy[:accept] if strategy[:accept]
        status = begin
          @http_client.get(strategy[:url], headers: headers).status
        rescue HttpClient::Error => e
          e.message[0, 60]
        end
        "#{strategy[:label]} → #{status}"
      end

      any_ok = results.any? { |line| line.end_with?("→ 200") }
      { status: any_ok ? "PASS" : "FAIL", note: any_ok ? "an authless strategy works" : "all JSON strategies blocked", evidence: results }
    end

    def raw_status(url)
      @http_client.get(url, headers: { "User-Agent" => Reddit::VotesFetcher::USER_AGENT }).status
    end
  end
end
