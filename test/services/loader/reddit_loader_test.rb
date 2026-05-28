require "test_helper"

class Loader::RedditLoaderTest < ActiveSupport::TestCase
  RSS_BODY = "<rss>reddit feed</rss>"

  def mock_client(url: nil)
    MockHttpClient.new(
      url: url,
      response: HttpClient::Response.new(status: 200, body: RSS_BODY)
    )
  end

  def loader(feed_url, http_client: nil)
    feed = create(:feed, feed_profile_key: "reddit", url: feed_url)
    opts = http_client ? { http_client: http_client } : {}
    Loader::RedditLoader.new(feed, opts)
  end

  test "#load should normalise short subreddit name to new.rss URL" do
    client = mock_client
    loader("r/worldnews", http_client: client).load
    assert_equal "https://www.reddit.com/r/worldnews/new.rss", client.last_request_url
  end

  test "#load should normalise short user name to new.rss URL" do
    client = mock_client
    loader("user/someuser", http_client: client).load
    assert_equal "https://www.reddit.com/user/someuser/new.rss", client.last_request_url
  end

  test "#load should normalise full subreddit URL to new.rss URL" do
    client = mock_client
    loader("https://www.reddit.com/r/programming/", http_client: client).load
    assert_equal "https://www.reddit.com/r/programming/new.rss", client.last_request_url
  end

  test "#load should normalise full user page URL to new.rss URL" do
    client = mock_client
    loader("https://www.reddit.com/user/someuser/", http_client: client).load
    assert_equal "https://www.reddit.com/user/someuser/new.rss", client.last_request_url
  end

  test "#load should normalise old.reddit.com URL to www.reddit.com new.rss URL" do
    client = mock_client
    loader("https://old.reddit.com/r/ruby/", http_client: client).load
    assert_equal "https://www.reddit.com/r/ruby/new.rss", client.last_request_url
  end

  test "#load should normalise existing .rss URL to new.rss URL" do
    client = mock_client
    loader("https://www.reddit.com/r/worldnews/.rss", http_client: client).load
    assert_equal "https://www.reddit.com/r/worldnews/new.rss", client.last_request_url
  end

  test "#load should return feed body on success" do
    result = loader("r/worldnews", http_client: mock_client).load
    assert_equal RSS_BODY, result
  end

  test "#load should raise on HTTP error" do
    feed = create(:feed, feed_profile_key: "reddit", url: "r/worldnews")
    error_client = MockHttpClient.new(response: HttpClient::Response.new(status: 429, body: "Too Many Requests"))
    error = assert_raises(StandardError) { Loader::RedditLoader.new(feed, { http_client: error_client }).load }
    assert_equal "HTTP 429", error.message
  end

  private

  class MockHttpClient
    attr_reader :last_request_url

    def initialize(url: nil, response: nil, error: nil)
      @response = response
      @error = error
    end

    def get(url)
      @last_request_url = url
      raise @error if @error
      @response
    end
  end
end
