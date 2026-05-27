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
