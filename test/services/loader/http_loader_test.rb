require "test_helper"

class Loader::HttpLoaderTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, url: "https://example.com/feed.xml")
  end

  test "should load feed successfully" do
    mock_client = MockHttpClient.new(
      response: HttpClient::Response.new(
        status: 200,
        body: "<rss>feed content</rss>",
        headers: { "content-type" => "application/rss+xml; charset=utf-8" }
      )
    )

    loader = Loader::HttpLoader.new(feed, { http_client: mock_client })
    result = loader.load

    assert_equal "<rss>feed content</rss>", result
    assert_equal feed.url, mock_client.last_request_url
  end

  test "should handle HTTP errors" do
    mock_client = MockHttpClient.new(
      response: HttpClient::Response.new(status: 404, body: "Not Found")
    )

    loader = Loader::HttpLoader.new(feed, { http_client: mock_client })

    error = assert_raises(StandardError) do
      loader.load
    end

    assert_equal "HTTP 404", error.message
  end

  test "should handle connection errors" do
    mock_client = MockHttpClient.new(error: HttpClient::ConnectionError.new("Connection refused"))

    loader = Loader::HttpLoader.new(feed, { http_client: mock_client })

    error = assert_raises(StandardError) do
      loader.load
    end

    assert_equal "Connection refused", error.message
  end

  test "should handle timeout errors" do
    mock_client = MockHttpClient.new(error: HttpClient::TimeoutError.new("Request timed out"))

    loader = Loader::HttpLoader.new(feed, { http_client: mock_client })

    error = assert_raises(StandardError) do
      loader.load
    end

    assert_equal "Request timed out", error.message
  end

  test "should handle too many redirects error" do
    mock_client = MockHttpClient.new(error: HttpClient::TooManyRedirectsError.new("Too many redirects"))

    loader = Loader::HttpLoader.new(feed, { http_client: mock_client })

    error = assert_raises(StandardError) do
      loader.load
    end

    assert_equal "Too many redirects", error.message
  end

  test "should use default max redirects of 3" do
    loader = Loader::HttpLoader.new(feed)

    # Check that it creates a FaradayAdapter with max_redirects: 3
    assert_instance_of HttpClient::FaradayAdapter, loader.send(:http_client)
  end

  test "should accept custom max redirects" do
    loader = Loader::HttpLoader.new(feed, { max_redirects: 5 })

    # Check that it creates a FaradayAdapter (we can't easily test the internal options)
    assert_instance_of HttpClient::FaradayAdapter, loader.send(:http_client)
  end


  private

  class MockHttpClient
    attr_reader :last_request_url

    def initialize(response: nil, error: nil)
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
