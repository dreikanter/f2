require "test_helper"

class FeedIdentificationFetcherTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

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
    recommended = feed_identification.candidates.first
    assert_equal "rss", recommended["profile_key"]
    assert_equal "Test RSS Feed", recommended["title"]
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
    assert_nil feed_identification.candidates.first["title"]
  end

  test "#identify should fall back to AI extraction when no structured profile matches" do
    url = "http://example.com/unknown.txt"

    stub_request(:get, url)
      .to_return(status: 200, body: "Not a valid feed format", headers: { "Content-Type" => "text/plain" })

    service = FeedIdentificationFetcher.new(user: user, input: url, logger: @logger)
    service.identify

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "success", feed_identification.status
    assert_equal "llm_website_extractor", feed_identification.candidates.first["profile_key"]
  end

  test "#identify should update record with failed status on HTTP errors" do
    url = "http://example.com/error.xml"

    stub_request(:get, url)
      .to_return(status: 500, body: "Internal Server Error")

    service = FeedIdentificationFetcher.new(user: user, input: url, logger: @logger)
    service.identify

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "failed", feed_identification.status
    assert_includes feed_identification.error, "An error occurred while identifying the feed"
  end

  test "#identify should broadcast the expanded form into feed-form on success" do
    url = "http://example.com/feed.xml"
    stub_request(:get, url)
      .to_return(status: 200, body: "<rss version=\"2.0\"><channel><title>Example</title></channel></rss>")

    feed_identification = FeedIdentification.create!(user: user, input: url, status: :processing, started_at: Time.current)

    broadcasts = capture_turbo_stream_broadcasts(feed_identification) do
      FeedIdentificationFetcher.new(user: user, input: url, logger: @logger).identify
    end

    assert_equal 1, broadcasts.size
    stream = broadcasts.first
    assert_equal "replace", stream["action"]
    assert_equal "feed-form", stream["target"]
    assert_includes stream.to_html, 'data-identification-state="complete"'
  end

  test "#identify should broadcast the error pane into feed-form on failure" do
    url = "http://example.com/error.xml"
    stub_request(:get, url).to_return(status: 500, body: "Internal Server Error")

    feed_identification = FeedIdentification.create!(user: user, input: url, status: :processing, started_at: Time.current)

    broadcasts = capture_turbo_stream_broadcasts(feed_identification) do
      FeedIdentificationFetcher.new(user: user, input: url, logger: @logger).identify
    end

    assert_equal 1, broadcasts.size
    stream = broadcasts.first
    assert_equal "replace", stream["action"]
    assert_equal "feed-form", stream["target"]
    assert_includes stream.to_html, 'data-identification-state="error"'
  end

  test "#identify should handle network errors gracefully" do
    url = "http://example.com/timeout.xml"

    stub_request(:get, url)
      .to_raise(HttpClient::TimeoutError.new("Connection timeout"))

    service = FeedIdentificationFetcher.new(user: user, input: url, logger: @logger)
    service.identify

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "failed", feed_identification.status
    assert_equal "An error occurred while identifying the feed", feed_identification.error
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
    assert_equal %w[rss llm_website_extractor], feed_identification.candidates.map { |c| c["profile_key"] }

    candidate = feed_identification.candidates.first
    assert_equal "rss", candidate["profile_key"]
    assert_equal "Example Feed", candidate["title"]
    assert_equal false, candidate["depends_on_ai"]
    assert_equal 0, candidate["rank"]
    assert_equal "specific_match", candidate["rank_reason"]
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
    assert_equal %w[xkcd rss llm_website_extractor], profile_keys, "xkcd > rss > AI fallback for xkcd.com URLs"
  end

  test "#identify should record the AI fallback as the only candidate when no structured profile matches" do
    url = "http://example.com/page.html"
    stub_request(:get, url).to_return(status: 200, body: "<html><body/></html>")

    FeedIdentificationFetcher.new(user: user, input: url, logger: @logger).identify

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_equal "success", feed_identification.status
    assert_equal ["llm_website_extractor"], feed_identification.candidates.map { |c| c["profile_key"] }
    assert_equal true, feed_identification.candidates.first["depends_on_ai"]
  end
end
