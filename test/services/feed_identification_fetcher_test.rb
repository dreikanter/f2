require "test_helper"

class FeedIdentificationFetcherTest < ActiveSupport::TestCase
  test "#call should not settle results under another worker configuration" do
    url = "https://wumo.com/wumo?view=rss"
    identification = create(:feed_identification, input: url, started_at: Time.current)
    attributes = identification.attributes
    stub_request(:get, url).to_return(status: 200, body: file_fixture("feeds/wumo/current.xml").read)

    stub_const(FeedProfile, :PROFILES, FeedProfile::PROFILES.except("wumo")) do
      FeedIdentificationFetcher.new(feed_identification: identification, run_id: identification.run_id).call
    end

    assert_requested :get, url
    assert_equal attributes, identification.reload.attributes
  end

  setup do
    @logger = ActiveSupport::Logger.new(nil) # Silent logger for tests
  end

  def user
    @user ||= create(:user)
  end

  test "#call should successfully identify RSS feed and update record" do
    url = "http://example.com/feed.xml"

    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test RSS Feed</title>
          <description>Test Description</description>
          <link>http://example.com</link>
          <item>
            <title>Test Post</title>
            <description>Test content</description>
            <link>http://example.com/post1</link>
          </item>
        </channel>
      </rss>
    XML

    stub_request(:get, url)
      .to_return(status: 200, body: rss_content, headers: { "Content-Type" => "application/xml" })

    fetcher(url).call

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "working", feed_identification.status
    assert_equal url, feed_identification.input
    suggested = feed_identification.candidates.first
    assert_equal "rss", suggested["profile_key"]
    assert_equal "Test RSS Feed", suggested["title"]

    events = identification_events
    assert_equal %w[debug], events.map(&:level).uniq
    assert_equal [user.id], events.map(&:user_id).uniq
    assert_equal [feed_identification.run_id], events.map { |event| event.metadata.dig("stats", "run_id") }.uniq
    assert_equal %w[fetch candidate result], events.map { |event| event.metadata.dig("stats", "stage") }
    assert_equal 200, events.first.metadata.dig("stats", "http_status")
    assert_equal rss_content.bytesize, events.first.metadata.dig("stats", "body_bytes")
    assert_equal "passed", events.second.metadata.dig("stats", "status")
    assert_equal 1, events.second.metadata.dig("stats", "posts_found")
    assert_equal "rss", events.last.metadata.dig("stats", "selected_profile")
    assert_not_includes events.to_json, "Test content"

    feed_identification.destroy!
    assert_equal events.map(&:id), identification_events.map(&:id)
  end

  test "#call should record blocked responses without URL secrets" do
    url = "https://example.com/feed.xml?token=secret"
    stub_request(:get, url).to_return(status: 403, headers: { "Content-Type" => "text/html" })

    fetcher("#{url}#private").call

    events = identification_events
    assert_equal %w[fetch result], events.map { |event| event.metadata.dig("stats", "stage") }
    assert_equal "https://example.com/feed.xml", events.first.metadata.dig("stats", "source_url")
    assert_equal "https://example.com/feed.xml", events.first.metadata.dig("stats", "resolved_url")
    assert_equal 403, events.first.metadata.dig("stats", "http_status")
    assert_equal "no_feed", events.last.metadata.dig("stats", "status")
    assert_match(/HTTP 403/, events.last.metadata.dig("stats", "error"))
    assert_no_match(/reader|password|secret|private/, events.to_json)
  end

  test "#call should record transport failures without URL secrets in error messages" do
    url = "https://example.com/feed.xml"
    stub_request(:get, url).to_raise(SocketError.new("Cannot reach https://reader:password@example.com/feed.xml?token=secret#private"))

    fetcher(url).call

    events = identification_events
    assert_equal %w[fetch result], events.map { |event| event.metadata.dig("stats", "stage") }
    assert_match(/Cannot reach https:\/\/example.com\/feed.xml/, events.first.message)
    assert_equal "unreachable", events.last.metadata.dig("stats", "status")
    assert_no_match(/reader|password|secret|private/, events.to_json)
  end

  test "#call should record candidate parser errors separately from chooser data" do
    url = "https://xkcd.com/rss.xml"
    stub_request(:get, url).to_return(status: 200, body: "<html>Temporarily unavailable</html>")

    fetcher(url).call

    event = identification_events.find { |item| item.metadata.dig("stats", "stage") == "candidate" }
    assert_equal "xkcd", event.metadata.dig("stats", "profile_key")
    assert_equal "failed", event.metadata.dig("stats", "status")
    assert_match(/NoParserAvailable/, event.metadata.dig("stats", "error"))
    assert_not FeedIdentification.find_by!(user: user, input: url).candidates.first.key?("error")
  end

  test "#call should successfully identify XKCD feed and update record" do
    url = "https://xkcd.com/rss.xml"

    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>xkcd.com</title>
          <link>https://xkcd.com/</link>
          <description>xkcd.com: A webcomic</description>
        </channel>
      </rss>
    XML

    stub_request(:get, url)
      .to_return(status: 200, body: rss_content, headers: { "Content-Type" => "application/xml" })

    fetcher(url).call

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "working", feed_identification.status
    assert_equal "xkcd", feed_identification.candidates.first["profile_key"]
  end

  test "#call should handle title extraction failure gracefully" do
    url = "http://example.com/feed.xml"

    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <description>Test Description</description>
        </channel>
      </rss>
    XML

    stub_request(:get, url)
      .to_return(status: 200, body: rss_content, headers: { "Content-Type" => "application/xml" })

    fetcher(url).call

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "example.com", feed_identification.candidates.first["title"]
    # The candidate is detected but reads nothing, so the run settles terminal.
    assert_equal "no_feed", feed_identification.status
    assert_equal "failed", feed_identification.candidates.first["test_status"]
  end

  test "#call should refuse a non-public URL without fetching it" do
    url = "http://127.0.0.1/feed.xml"
    stub_request(:get, url) # should never be hit

    fetcher(url).call

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_equal "no_feed", feed_identification.status
    assert_not_requested :get, url
  end

  test "#call should settle as no_feed when no structured profile matches" do
    # The AI profile registers no matcher, so a reachable page with no
    # standard feed yields no candidates; the entry flow offers the AI bridge.
    url = "http://example.com/unknown.txt"

    stub_request(:get, url)
      .to_return(status: 200, body: "Not a valid feed format", headers: { "Content-Type" => "text/plain" })

    fetcher(url).call

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "no_feed", feed_identification.status
  end

  test "#call should mark a bad response status as no_feed (reachable, terminal)" do
    url = "http://example.com/error.xml"

    stub_request(:get, url)
      .to_return(status: 500, body: "Internal Server Error")

    fetcher(url).call

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "no_feed", feed_identification.status
  end

  test "#call should mark a redirect loop as no_feed" do
    url = "http://example.com/loop.xml"

    stub_request(:get, url)
      .to_raise(HttpClient::TooManyRedirectsError.new("too many redirects"))

    fetcher(url).call

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_equal "no_feed", feed_identification.status
  end

  test "#call should mark a connection failure as unreachable (transient)" do
    url = "http://example.com/timeout.xml"

    stub_request(:get, url)
      .to_raise(HttpClient::TimeoutError.new("Connection timeout"))

    fetcher(url).call

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "unreachable", feed_identification.status
  end

  test "#call should log the failure class and status for diagnosis" do
    url = "http://example.com/error.xml"
    stub_request(:get, url).to_return(status: 404, body: "Not Found")

    log = StringIO.new
    fetcher(url, logger: ActiveSupport::Logger.new(log)).call

    assert_match(/ResponseStatusError \(HTTP 404\)/, log.string)
  end

  test "#call should settle as no_feed and report an unexpected failure" do
    url = "http://example.com/feed.xml"
    stub_request(:get, url).to_return(status: 200, body: "<rss></rss>")

    FeedProfileDetector.stub(:call, proc { raise "boom" }) do
      fetcher(url).call
    end

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_equal "no_feed", feed_identification.status
  end

  test "#call should settle as no_feed when no candidates are detected" do
    url = "http://example.com/feed.xml"
    stub_request(:get, url).to_return(status: 200, body: "x")

    empty_result = Struct.new(:candidates).new([])
    FeedProfileDetector.stub(:call, empty_result) do
      fetcher(url).call
    end

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_equal "no_feed", feed_identification.status
  end

  test "#call should persist a ranked candidates array on success" do
    url = "http://example.com/feed.xml"

    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Example Feed</title>
        </channel>
      </rss>
    XML

    stub_request(:get, url).to_return(status: 200, body: rss_content)

    fetcher(url).call

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_equal %w[rss], feed_identification.candidates.map { |c| c["profile_key"] }

    candidate = feed_identification.candidates.first
    assert_equal "rss", candidate["profile_key"]
    assert_equal "Example Feed", candidate["title"]

    # Empty-but-valid source still passes the self-test, flagged with zero posts found.
    assert_equal "passed", candidate["test_status"]
    assert_equal 0, candidate["posts_found"]
  end

  test "#call should fetch each source URL once across matching and testing" do
    url = "http://example.com/feed.xml"

    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel><title>Example Feed</title></channel>
      </rss>
    XML

    stub_request(:get, url).to_return(status: 200, body: rss_content)

    fetcher(url).call

    assert_requested :get, url, times: 1
  end

  test "#call should persist multiple candidates ranked when multiple match" do
    url = "https://xkcd.com/rss.xml"

    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>xkcd.com</title>
        </channel>
      </rss>
    XML

    stub_request(:get, url).to_return(status: 200, body: rss_content)

    fetcher(url).call

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    profile_keys = feed_identification.candidates.map { |c| c["profile_key"] }
    assert_equal %w[xkcd rss], profile_keys, "xkcd > rss for xkcd.com URLs"
  end

  test "#call should not tag directly identified candidates with a resolved URL" do
    url = "http://example.com/feed.xml"
    stub_request(:get, url).to_return(status: 200, body: rss_body("Direct Feed"))

    fetcher(url).call

    candidate = FeedIdentification.find_by(user: user, input: url).candidates.first
    assert_nil candidate["resolved_url"]
  end

  test "#call should discover the feed a page advertises" do
    page_url = "http://example.com/blog"
    feed_url = "http://example.com/feed.xml"

    stub_request(:get, page_url).to_return(status: 200, body: page_body(%(<link rel="alternate" type="application/rss+xml" href="/feed.xml">)))
    stub_request(:get, feed_url).to_return(status: 200, body: rss_body("Discovered Feed"))

    fetcher(page_url).call

    feed_identification = FeedIdentification.find_by(user: user, input: page_url)
    assert_equal "working", feed_identification.status

    candidate = feed_identification.suggested_candidate
    assert_equal "rss", candidate.profile_key
    assert_equal "Discovered Feed", candidate.title
    assert_equal feed_url, candidate.resolved_url
    assert_equal feed_url, feed_identification.source_url_for("rss")
  end

  test "#call should resolve relative feed links against the final redirected URL" do
    stub_request(:get, "http://example.com/").to_return(status: 301, headers: { "Location" => "http://www.example.com/blog/" })
    stub_request(:get, "http://www.example.com/blog/").to_return(status: 200, body: page_body(%(<link rel="alternate" type="application/rss+xml" href="feed.xml">)))
    stub_request(:get, "http://www.example.com/blog/feed.xml").to_return(status: 200, body: rss_body("Moved Feed"))

    fetcher("http://example.com/").call

    feed_identification = FeedIdentification.find_by(user: user, input: "http://example.com/")
    assert_equal "working", feed_identification.status
    assert_equal "http://www.example.com/blog/feed.xml", feed_identification.suggested_candidate.resolved_url
  end

  test "#call should keep trying advertised feeds until one works" do
    page_url = "http://example.com/blog"
    links = <<~HTML
      <link rel="alternate" type="application/rss+xml" href="/missing.xml">
      <link rel="alternate" type="application/atom+xml" href="/feed.xml">
    HTML

    stub_request(:get, page_url).to_return(status: 200, body: page_body(links))
    stub_request(:get, "http://example.com/missing.xml").to_return(status: 404)
    stub_request(:get, "http://example.com/feed.xml").to_return(status: 200, body: rss_body("Second Feed"))

    fetcher(page_url).call

    feed_identification = FeedIdentification.find_by(user: user, input: page_url)
    assert_equal "working", feed_identification.status
    assert_equal "http://example.com/feed.xml", feed_identification.suggested_candidate.resolved_url

    fetches = identification_events.select { |event| event.metadata.dig("stats", "stage") == "fetch" }
    assert_equal [page_url, "http://example.com/missing.xml", "http://example.com/feed.xml"],
                 fetches.map { |event| event.metadata.dig("stats", "source_url") }
    assert_equal [200, 404, 200], fetches.map { |event| event.metadata.dig("stats", "http_status") }
  end

  test "#call should stop at the first advertised feed that works" do
    page_url = "http://example.com/blog"
    links = <<~HTML
      <link rel="alternate" type="application/rss+xml" href="/feed.xml">
      <link rel="alternate" type="application/rss+xml" href="/comments.xml">
    HTML

    stub_request(:get, page_url).to_return(status: 200, body: page_body(links))
    stub_request(:get, "http://example.com/feed.xml").to_return(status: 200, body: rss_body("Main Feed"))
    stub_request(:get, "http://example.com/comments.xml").to_return(status: 200, body: rss_body("Comments Feed"))

    fetcher(page_url).call

    feed_identification = FeedIdentification.find_by(user: user, input: page_url)
    assert_equal %w[http://example.com/feed.xml], feed_identification.working_candidates.map(&:resolved_url).uniq
    assert_not_requested :get, "http://example.com/comments.xml"
  end

  test "#call should stay no_feed when no advertised feed works" do
    page_url = "http://example.com/blog"

    stub_request(:get, page_url).to_return(status: 200, body: page_body(%(<link rel="alternate" type="application/rss+xml" href="/gone.xml">)))
    stub_request(:get, "http://example.com/gone.xml").to_return(status: 404)

    fetcher(page_url).call

    feed_identification = FeedIdentification.find_by(user: user, input: page_url)
    assert_equal "no_feed", feed_identification.status
  end

  test "#call should settle as unreachable when every candidate dies on the network" do
    url = "http://example.com/feed.xml"
    stub_request(:get, url).to_return(status: 200, body: "x")

    detected = Struct.new(:candidates).new([Struct.new(:profile_key).new("rss")])
    verdict = CandidateTester::Result.new(status: FeedIdentification::Candidate::UNREACHABLE, posts_found: 0)

    FeedProfileDetector.stub(:call, detected) do
      CandidateTester.stub(:new, ->(**) { Struct.new(:call).new(verdict) }) do
        fetcher(url).call
      end
    end

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_equal "unreachable", feed_identification.status
    assert_equal "unreachable", feed_identification.candidates.first["test_status"]
  end

  test "#call should settle as no_feed when candidates mix network and parse failures" do
    url = "http://example.com/feed.xml"
    stub_request(:get, url).to_return(status: 200, body: "x")

    detected = Struct.new(:candidates).new([
      Struct.new(:profile_key).new("rss"),
      Struct.new(:profile_key).new("atom")
    ])
    verdicts = [
      CandidateTester::Result.new(status: FeedIdentification::Candidate::UNREACHABLE, posts_found: 0),
      CandidateTester::Result.new(status: FeedIdentification::Candidate::FAILED, posts_found: 0)
    ]

    FeedProfileDetector.stub(:call, detected) do
      CandidateTester.stub(:new, ->(**) { Struct.new(:call).new(verdicts.shift) }) do
        fetcher(url).call
      end
    end

    assert_equal "no_feed", FeedIdentification.find_by(user: user, input: url).status
  end

  test "#call should not follow an advertised feed's redirect to a private address" do
    page_url = "http://example.com/blog"

    stub_request(:get, page_url).to_return(status: 200, body: page_body(%(<link rel="alternate" type="application/rss+xml" href="/feed.xml">)))
    stub_request(:get, "http://example.com/feed.xml")
      .to_return(status: 302, headers: { "Location" => "http://127.0.0.1/feed.xml" })

    fetcher(page_url).call

    assert_equal "no_feed", FeedIdentification.find_by(user: user, input: page_url).status
    assert_not_requested :get, "http://127.0.0.1/feed.xml"
  end

  test "#call should fall back to advertised feeds when a matched candidate fails its test" do
    page_url = "http://example.com/blog"
    html = <<~HTML
      <html><head>
        <link rel="alternate" type="application/rss+xml" href="/feed.xml">
      </head><body>
        <p>Example markup:</p>
        <pre><rss version="2.0"><channel></channel></rss></pre>
      </body></html>
    HTML

    stub_request(:get, page_url).to_return(status: 200, body: html)
    stub_request(:get, "http://example.com/feed.xml").to_return(status: 200, body: rss_body("Real Feed"))

    fetcher(page_url).call

    feed_identification = FeedIdentification.find_by(user: user, input: page_url)
    assert_equal "working", feed_identification.status
    assert_equal "http://example.com/feed.xml", feed_identification.suggested_candidate.resolved_url
  end

  test "#call should never fetch a non-public advertised feed URL" do
    page_url = "http://example.com/blog"

    stub_request(:get, page_url).to_return(status: 200, body: page_body(%(<link rel="alternate" type="application/rss+xml" href="http://127.0.0.1/feed.xml">)))

    fetcher(page_url).call

    assert_equal "no_feed", FeedIdentification.find_by(user: user, input: page_url).status
    assert_not_requested :get, "http://127.0.0.1/feed.xml"
  end

  test "#call should ignore a result after timeout rotates run_id" do
    url = "http://example.com/feed.xml"
    run_id = SecureRandom.uuid
    identification = create(:feed_identification, user: user, input: url, status: :processing,
                                                   started_at: Time.current, run_id: run_id)
    stale_fetcher = FeedIdentificationFetcher.new(
      feed_identification: identification,
      run_id: run_id,
      logger: @logger
    )
    stub_request(:get, url).to_return(status: 200, body: rss_body("Late Feed"))

    FeedIdentificationTimeoutJob.perform_now(identification.id, run_id)
    stale_fetcher.call

    assert_predicate identification.reload, :timed_out?
    assert_empty identification.candidates
    refute_equal run_id, identification.run_id
    result = identification_events.last
    assert_equal run_id, result.metadata.dig("stats", "run_id")
    assert_equal false, result.metadata.dig("stats", "applied")
    assert_match(/discarded/, result.message)
  end

  test "#call should ignore an error transition from a superseded run" do
    url = "http://example.com/feed.xml"
    stale_run_id = SecureRandom.uuid
    identification = create(:feed_identification, user: user, input: url, status: :processing,
                                                   started_at: Time.current, run_id: stale_run_id)
    stale_fetcher = FeedIdentificationFetcher.new(
      feed_identification: identification,
      run_id: stale_run_id,
      logger: @logger
    )
    identification.update!(run_id: SecureRandom.uuid)
    original_attributes = identification.attributes.slice("status", "run_id", "candidates", "updated_at")
    stub_request(:get, url).to_timeout

    stale_fetcher.call

    assert_equal original_attributes,
                 identification.reload.attributes.slice("status", "run_id", "candidates", "updated_at")
  end

  private

  def identification_events
    Event.where(type: "feed_identification", user: user).order(:id).to_a
  end

  def fetcher(input, logger: @logger)
    run_id = SecureRandom.uuid
    identification = create(:feed_identification, user: user, input: input, status: :processing,
                                                   started_at: Time.current, run_id: run_id)
    FeedIdentificationFetcher.new(feed_identification: identification, run_id: run_id, logger: logger)
  end

  def page_body(links)
    "<html><head><title>My Blog</title>#{links}</head><body>Posts</body></html>"
  end

  def rss_body(title)
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>#{title}</title>
          <link>http://example.com</link>
          <item>
            <title>Hello</title>
            <description>World</description>
            <link>http://example.com/post1</link>
          </item>
        </channel>
      </rss>
    XML
  end
end
