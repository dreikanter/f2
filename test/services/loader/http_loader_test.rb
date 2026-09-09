require "test_helper"

class Loader::HttpLoaderTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, url: "https://example.com/feed.xml")
  end

  test "#load should retrieve feed content" do
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

  test "#load should handle HTTP errors" do
    mock_client = MockHttpClient.new(
      response: HttpClient::Response.new(status: 404, body: "Not Found")
    )

    loader = Loader::HttpLoader.new(feed, { http_client: mock_client })

    error = assert_raises(Loader::Error) do
      loader.load
    end

    assert_equal "HTTP 404", error.message
  end

  test "#load should handle connection errors" do
    mock_client = MockHttpClient.new(error: HttpClient::ConnectionError.new("Connection refused"))

    loader = Loader::HttpLoader.new(feed, { http_client: mock_client })

    error = assert_raises(Loader::Error) do
      loader.load
    end

    assert_equal "Connection refused", error.message
  end

  test "#load should handle timeout errors" do
    mock_client = MockHttpClient.new(error: HttpClient::TimeoutError.new("Request timed out"))

    loader = Loader::HttpLoader.new(feed, { http_client: mock_client })

    error = assert_raises(Loader::Error) do
      loader.load
    end

    assert_equal "Request timed out", error.message
  end

  test "#load should handle too many redirects error" do
    mock_client = MockHttpClient.new(error: HttpClient::TooManyRedirectsError.new("Too many redirects"))

    loader = Loader::HttpLoader.new(feed, { http_client: mock_client })

    error = assert_raises(Loader::Error) do
      loader.load
    end

    assert_equal "Too many redirects", error.message
  end

  test "#load should stop after three redirects by default" do
    stub_redirect_chain

    error = assert_raises(Loader::Error) { Loader::HttpLoader.new(feed).load }

    assert_instance_of HttpClient::TooManyRedirectsError, error.cause
    assert_requested :get, "https://example.com/redirect-3", times: 1
    assert_not_requested :get, "https://example.com/redirect-4"
  end

  test "#load should honor a custom redirect limit" do
    stub_redirect_chain

    result = Loader::HttpLoader.new(feed, max_redirects: 4).load

    assert_equal "<rss>feed content</rss>", result
    assert_requested :get, "https://example.com/redirect-4", times: 1
  end

  private

  def stub_redirect_chain
    urls = [feed.url] + (1..4).map { |i| "https://example.com/redirect-#{i}" }
    urls.each_cons(2) do |source, target|
      stub_request(:get, source).to_return(status: 302, headers: { "Location" => target })
    end
    stub_request(:get, urls.last).to_return(body: "<rss>feed content</rss>")
  end

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
