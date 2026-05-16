require "test_helper"

class FeedDetailsFetcherTest < ActiveSupport::TestCase
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

    service = FeedDetailsFetcher.new(user: user, url: url, logger: @logger)
    service.identify

    feed_detail = FeedDetail.find_by(user: user, url: url)
    assert_not_nil feed_detail
    assert_equal "success", feed_detail.status
    assert_equal url, feed_detail.url
    assert_equal "rss", feed_detail.feed_profile_key
    assert_equal "Test RSS Feed", feed_detail.title
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

    service = FeedDetailsFetcher.new(user: user, url: url, logger: @logger)
    service.identify

    feed_detail = FeedDetail.find_by(user: user, url: url)
    assert_not_nil feed_detail
    assert_equal "success", feed_detail.status
    assert_equal "xkcd", feed_detail.feed_profile_key
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

    service = FeedDetailsFetcher.new(user: user, url: url, logger: @logger)
    service.identify

    feed_detail = FeedDetail.find_by(user: user, url: url)
    assert_not_nil feed_detail
    assert_equal "success", feed_detail.status
    assert_nil feed_detail.title
  end

  test "#identify should update record with failed status when profile not identified" do
    url = "http://example.com/unknown.txt"

    stub_request(:get, url)
      .to_return(status: 200, body: "Not a valid feed format", headers: { "Content-Type" => "text/plain" })

    service = FeedDetailsFetcher.new(user: user, url: url, logger: @logger)
    service.identify

    feed_detail = FeedDetail.find_by(user: user, url: url)
    assert_not_nil feed_detail
    assert_equal "failed", feed_detail.status
    assert_equal "Unsupported feed profile", feed_detail.error
  end

  test "#identify should update record with failed status on HTTP errors" do
    url = "http://example.com/error.xml"

    stub_request(:get, url)
      .to_return(status: 500, body: "Internal Server Error")

    service = FeedDetailsFetcher.new(user: user, url: url, logger: @logger)
    service.identify

    feed_detail = FeedDetail.find_by(user: user, url: url)
    assert_not_nil feed_detail
    assert_equal "failed", feed_detail.status
    assert_includes feed_detail.error, "An error occurred while identifying the feed"
  end

  test "#identify should handle network errors gracefully" do
    url = "http://example.com/timeout.xml"

    stub_request(:get, url)
      .to_raise(HttpClient::TimeoutError.new("Connection timeout"))

    service = FeedDetailsFetcher.new(user: user, url: url, logger: @logger)
    service.identify

    feed_detail = FeedDetail.find_by(user: user, url: url)
    assert_not_nil feed_detail
    assert_equal "failed", feed_detail.status
    assert_equal "An error occurred while identifying the feed", feed_detail.error
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

    FeedDetailsFetcher.new(user: user, url: url, logger: @logger).identify

    feed_detail = FeedDetail.find_by(user: user, url: url)
    assert_equal 1, feed_detail.candidates.size

    candidate = feed_detail.candidates.first
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

    FeedDetailsFetcher.new(user: user, url: url, logger: @logger).identify

    feed_detail = FeedDetail.find_by(user: user, url: url)
    profile_keys = feed_detail.candidates.map { |c| c["profile_key"] }
    assert_equal %w[xkcd rss], profile_keys, "xkcd outranks rss for xkcd.com URLs"
    assert_equal "xkcd", feed_detail.feed_profile_key, "feed_profile_key mirrors the recommended candidate"
  end

  test "#identify should persist an empty candidates array when no profile matches" do
    url = "http://example.com/page.html"
    stub_request(:get, url).to_return(status: 200, body: "<html><body/></html>")

    FeedDetailsFetcher.new(user: user, url: url, logger: @logger).identify

    feed_detail = FeedDetail.find_by(user: user, url: url)
    assert_equal "failed", feed_detail.status
    assert_equal [], feed_detail.candidates
  end
end
