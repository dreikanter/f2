require "test_helper"

class FeedIdentificationFetcherTest < ActiveSupport::TestCase
  setup do
    @logger = ActiveSupport::Logger.new(nil) # Silent logger for tests
  end

  def user
    @user ||= create(:user)
  end

  test "#identify should successfully identify RSS feed and update record" do
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

    service = FeedIdentificationFetcher.new(user: user, input: url, logger: @logger)
    service.identify

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "success", feed_identification.status
    assert_equal url, feed_identification.input
    suggested = feed_identification.candidates.first
    assert_equal "rss", suggested["profile_key"]
    assert_equal "Test RSS Feed", suggested["title"]
  end

  test "#identify should successfully identify XKCD feed and update record" do
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

    service = FeedIdentificationFetcher.new(user: user, input: url, logger: @logger)
    service.identify

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "success", feed_identification.status
    assert_equal "xkcd", feed_identification.candidates.first["profile_key"]
  end

  test "#identify should handle title extraction failure gracefully" do
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

    service = FeedIdentificationFetcher.new(user: user, input: url, logger: @logger)
    service.identify

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "success", feed_identification.status
    assert_equal "example.com", feed_identification.candidates.first["title"]
  end

  test "#identify should refuse a non-public URL without fetching it" do
    url = "http://127.0.0.1/feed.xml"
    stub_request(:get, url) # should never be hit

    FeedIdentificationFetcher.new(user: user, input: url, logger: @logger).identify

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_equal "failed", feed_identification.status
    assert_equal "unreadable", feed_identification.error
    assert_not_requested :get, url
  end

  test "#identify should fail as unidentifiable when no structured profile matches" do
    # The AI profile registers no matcher (spec §7), so a reachable page with no
    # standard feed yields no candidates — the entry flow offers the AI bridge.
    url = "http://example.com/unknown.txt"

    stub_request(:get, url)
      .to_return(status: 200, body: "Not a valid feed format", headers: { "Content-Type" => "text/plain" })

    service = FeedIdentificationFetcher.new(user: user, input: url, logger: @logger)
    service.identify

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "failed", feed_identification.status
    assert_equal "unidentifiable", feed_identification.error
  end

  test "#identify should mark a bad response status as unreadable (reachable, no feed)" do
    url = "http://example.com/error.xml"

    stub_request(:get, url)
      .to_return(status: 500, body: "Internal Server Error")

    service = FeedIdentificationFetcher.new(user: user, input: url, logger: @logger)
    service.identify

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "failed", feed_identification.status
    assert_equal "unreadable", feed_identification.error
  end

  test "#identify should mark a redirect loop as unreadable" do
    url = "http://example.com/loop.xml"

    stub_request(:get, url)
      .to_raise(HttpClient::TooManyRedirectsError.new("too many redirects"))

    service = FeedIdentificationFetcher.new(user: user, input: url, logger: @logger)
    service.identify

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_equal "failed", feed_identification.status
    assert_equal "unreadable", feed_identification.error
  end

  test "#identify should mark a connection failure as unreachable (transient)" do
    url = "http://example.com/timeout.xml"

    stub_request(:get, url)
      .to_raise(HttpClient::TimeoutError.new("Connection timeout"))

    service = FeedIdentificationFetcher.new(user: user, input: url, logger: @logger)
    service.identify

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "failed", feed_identification.status
    assert_equal "unreachable", feed_identification.error
  end

  test "#identify should log the failure class and status for diagnosis" do
    url = "http://example.com/error.xml"
    stub_request(:get, url).to_return(status: 404, body: "Not Found")

    log = StringIO.new
    FeedIdentificationFetcher.new(user: user, input: url, logger: ActiveSupport::Logger.new(log)).identify

    assert_match(/ResponseStatusError \(HTTP 404\)/, log.string)
  end

  test "#identify should record internal_error and report an unexpected failure" do
    url = "http://example.com/feed.xml"
    stub_request(:get, url).to_return(status: 200, body: "<rss></rss>")

    FeedProfileDetector.stub(:call, proc { raise "boom" }) do
      FeedIdentificationFetcher.new(user: user, input: url, logger: @logger).identify
    end

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_equal "failed", feed_identification.status
    assert_equal "internal_error", feed_identification.error
  end

  test "#identify should record unidentifiable when no candidates are detected" do
    url = "http://example.com/feed.xml"
    stub_request(:get, url).to_return(status: 200, body: "x")

    empty_result = Struct.new(:candidates).new([])
    FeedProfileDetector.stub(:call, empty_result) do
      FeedIdentificationFetcher.new(user: user, input: url, logger: @logger).identify
    end

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_equal "failed", feed_identification.status
    assert_equal "unidentifiable", feed_identification.error
  end

  test "#identify should persist a ranked candidates array on success" do
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

    FeedIdentificationFetcher.new(user: user, input: url, logger: @logger).identify

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_equal %w[rss], feed_identification.candidates.map { |c| c["profile_key"] }

    candidate = feed_identification.candidates.first
    assert_equal "rss", candidate["profile_key"]
    assert_equal "Example Feed", candidate["title"]

    # Empty-but-valid source still passes the self-test, flagged with zero posts found.
    assert_equal "passed", candidate["test_status"]
    assert_equal 0, candidate["posts_found"]
  end

  test "#identify should fetch each source URL once across matching and testing" do
    url = "http://example.com/feed.xml"

    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel><title>Example Feed</title></channel>
      </rss>
    XML

    stub_request(:get, url).to_return(status: 200, body: rss_content)

    FeedIdentificationFetcher.new(user: user, input: url, logger: @logger).identify

    assert_requested :get, url, times: 1
  end

  test "#identify should persist multiple candidates ranked when multiple match" do
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

    FeedIdentificationFetcher.new(user: user, input: url, logger: @logger).identify

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    profile_keys = feed_identification.candidates.map { |c| c["profile_key"] }
    assert_equal %w[xkcd rss], profile_keys, "xkcd > rss for xkcd.com URLs"
  end
end
