require "test_helper"

class Loader::YoutubeLoaderTest < ActiveSupport::TestCase
  FEED_URL = "https://www.youtube.com/feeds/videos.xml?channel_id=UC123"
  CHANNEL_URL = "https://www.youtube.com/@TestChannel"
  FEED_BODY = "<feed>...</feed>"

  CHANNEL_PAGE_WITH_RSS = <<~HTML
    <html><head>
      <link rel="alternate" type="application/rss+xml" title="RSS" href="#{FEED_URL}">
    </head><body></body></html>
  HTML

  CHANNEL_PAGE_WITH_ATOM = <<~HTML
    <html><head>
      <link rel="alternate" type="application/atom+xml" title="Atom" href="#{FEED_URL}">
    </head><body></body></html>
  HTML

  def feed_with_url(url)
    create(:feed, url: url)
  end

  test "#load should fetch feed URL directly when URL is already a feed URL" do
    feed = feed_with_url(FEED_URL)
    mock_client = MockHttpClient.new(responses: { FEED_URL => ok(FEED_BODY) })

    loader = Loader::YoutubeLoader.new(feed, { http_client: mock_client })

    assert_equal FEED_BODY, loader.load
    assert_equal [FEED_URL], mock_client.requested_urls
  end

  test "#load should resolve channel URL to feed URL via RSS link" do
    feed = feed_with_url(CHANNEL_URL)
    mock_client = MockHttpClient.new(responses: {
      CHANNEL_URL => ok(CHANNEL_PAGE_WITH_RSS),
      FEED_URL => ok(FEED_BODY)
    })

    loader = Loader::YoutubeLoader.new(feed, { http_client: mock_client })

    assert_equal FEED_BODY, loader.load
    assert_equal [CHANNEL_URL, FEED_URL], mock_client.requested_urls
  end

  test "#load should resolve channel URL to feed URL via Atom link" do
    feed = feed_with_url(CHANNEL_URL)
    mock_client = MockHttpClient.new(responses: {
      CHANNEL_URL => ok(CHANNEL_PAGE_WITH_ATOM),
      FEED_URL => ok(FEED_BODY)
    })

    loader = Loader::YoutubeLoader.new(feed, { http_client: mock_client })

    assert_equal FEED_BODY, loader.load
  end

  test "#load should raise when channel page has no RSS link" do
    feed = feed_with_url(CHANNEL_URL)
    mock_client = MockHttpClient.new(responses: {
      CHANNEL_URL => ok("<html><body>No RSS here</body></html>")
    })

    loader = Loader::YoutubeLoader.new(feed, { http_client: mock_client })

    error = assert_raises(StandardError) { loader.load }
    assert_match "Could not find YouTube RSS feed link", error.message
  end

  test "#load should raise on HTTP error for feed URL" do
    feed = feed_with_url(FEED_URL)
    mock_client = MockHttpClient.new(responses: { FEED_URL => error_response(404) })

    loader = Loader::YoutubeLoader.new(feed, { http_client: mock_client })

    error = assert_raises(StandardError) { loader.load }
    assert_equal "HTTP 404", error.message
  end

  test "#load should raise on HTTP error for channel page" do
    feed = feed_with_url(CHANNEL_URL)
    mock_client = MockHttpClient.new(responses: { CHANNEL_URL => error_response(403) })

    loader = Loader::YoutubeLoader.new(feed, { http_client: mock_client })

    error = assert_raises(StandardError) { loader.load }
    assert_equal "HTTP 403", error.message
  end

  test "#load should handle connection errors" do
    feed = feed_with_url(FEED_URL)
    mock_client = MockHttpClient.new(error: HttpClient::ConnectionError.new("Connection refused"))

    loader = Loader::YoutubeLoader.new(feed, { http_client: mock_client })

    error = assert_raises(StandardError) { loader.load }
    assert_equal "Connection refused", error.message
  end

  test "#load should resolve /channel/UCxxx URL to feed URL without fetching channel page" do
    channel_url = "https://www.youtube.com/channel/UCabc123def456ghi789jkl"
    expected_feed_url = "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc123def456ghi789jkl"
    feed = feed_with_url(channel_url)
    mock_client = MockHttpClient.new(responses: { expected_feed_url => ok(FEED_BODY) })

    loader = Loader::YoutubeLoader.new(feed, { http_client: mock_client })

    assert_equal FEED_BODY, loader.load
    assert_equal [expected_feed_url], mock_client.requested_urls
  end

  test "#load should resolve /user/Username URL to feed URL without fetching channel page" do
    user_url = "https://www.youtube.com/user/SampleTechChannel"
    expected_feed_url = "https://www.youtube.com/feeds/videos.xml?user=SampleTechChannel"
    feed = feed_with_url(user_url)
    mock_client = MockHttpClient.new(responses: { expected_feed_url => ok(FEED_BODY) })

    loader = Loader::YoutubeLoader.new(feed, { http_client: mock_client })

    assert_equal FEED_BODY, loader.load
    assert_equal [expected_feed_url], mock_client.requested_urls
  end

  test "#load should resolve playlist URL to feed URL without fetching channel page" do
    playlist_url = "https://www.youtube.com/playlist?list=PLabc123def456"
    expected_feed_url = "https://www.youtube.com/feeds/videos.xml?playlist_id=PLabc123def456"
    feed = feed_with_url(playlist_url)
    mock_client = MockHttpClient.new(responses: { expected_feed_url => ok(FEED_BODY) })

    loader = Loader::YoutubeLoader.new(feed, { http_client: mock_client })

    assert_equal FEED_BODY, loader.load
    assert_equal [expected_feed_url], mock_client.requested_urls
  end

  test "#load should fall back to HTML scraping for @handle URLs" do
    handle_url = "https://www.youtube.com/@SampleChannel"
    feed = feed_with_url(handle_url)
    mock_client = MockHttpClient.new(responses: {
      handle_url => ok(CHANNEL_PAGE_WITH_RSS),
      FEED_URL => ok(FEED_BODY)
    })

    loader = Loader::YoutubeLoader.new(feed, { http_client: mock_client })

    assert_equal FEED_BODY, loader.load
    assert_equal [handle_url, FEED_URL], mock_client.requested_urls
  end

  private

  def ok(body)
    HttpClient::Response.new(status: 200, body: body, headers: {})
  end

  def error_response(status)
    HttpClient::Response.new(status: status, body: "Error")
  end

  class MockHttpClient
    attr_reader :requested_urls

    def initialize(responses: {}, error: nil)
      @responses = responses
      @error = error
      @requested_urls = []
    end

    def get(url)
      @requested_urls << url
      raise @error if @error

      @responses.fetch(url) { raise KeyError, "Unexpected URL: #{url}" }
    end
  end
end
