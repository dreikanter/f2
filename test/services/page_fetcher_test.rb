require "test_helper"

class PageFetcherTest < ActiveSupport::TestCase
  PAGE_URL = "https://example.com/article"

  test "#fetch should return the successful response body" do
    stub_request(:get, PAGE_URL).to_return(status: 200, body: "<html>Sample article</html>")

    assert_equal "<html>Sample article</html>", PageFetcher.new.fetch(PAGE_URL)
  end

  test "#fetch should preserve an empty successful response" do
    stub_request(:get, PAGE_URL).to_return(status: 204, body: "")

    assert_equal "", PageFetcher.new.fetch(PAGE_URL)
  end

  test "#fetch should skip blank URLs without requesting a page" do
    fetcher = PageFetcher.new

    [nil, "", " "].each { |url| assert_nil fetcher.fetch(url) }

    assert_not_requested :get, /./
  end

  test "#fetch should retain HTTP failure details with context" do
    stub_request(:get, PAGE_URL).to_return(status: 503, body: "Service unavailable")
    fetcher = PageFetcher.new(context: { source: "sample" })

    assert_nil fetcher.fetch(PAGE_URL)

    assert_equal({ source: "sample", url: PAGE_URL, status: 503, message: "HTTP 503" }, fetcher.failures.sole)
    assert_requested :get, PAGE_URL, times: 1
  end

  test "#fetch should return nil for connection failures without reporting a bug" do
    stub_request(:get, PAGE_URL).to_raise(Faraday::ConnectionFailed.new("connection refused"))
    fetcher = PageFetcher.new

    reports = capture_error_reports { assert_nil fetcher.fetch(PAGE_URL) }

    assert_empty reports
    assert_equal "HttpClient::ConnectionError", fetcher.failures.sole[:error_class]
    assert_includes fetcher.failures.sole[:message], "connection refused"
    assert_requested :get, PAGE_URL, times: 1
  end

  test "#fetch should return nil for timeouts without reporting a bug" do
    stub_request(:get, PAGE_URL).to_timeout

    reports = capture_error_reports { assert_nil PageFetcher.new.fetch(PAGE_URL) }

    assert_empty reports
    assert_requested :get, PAGE_URL, times: 1
  end

  test "#fetch should still report other HTTP client errors with context" do
    stub_request(:get, PAGE_URL).to_raise(HttpClient::TooManyRedirectsError.new("Too many redirects"))
    context = { source: "sample" }
    reported = []

    Rails.error.stub(:report, ->(error, **options) { reported << [error, options] }) do
      assert_nil PageFetcher.new(context: context).fetch(PAGE_URL)
    end

    assert_equal 1, reported.size
    error, options = reported.first
    assert_kind_of HttpClient::TooManyRedirectsError, error
    assert_equal :warning, options[:severity]
    assert_equal({ source: "sample", url: PAGE_URL }, options[:context])
    assert_requested :get, PAGE_URL, times: 1
  end

  test "#fetch should let unexpected errors propagate" do
    stub_request(:get, PAGE_URL).to_raise(ArgumentError.new("unexpected error"))

    assert_raises(ArgumentError) { PageFetcher.new.fetch(PAGE_URL) }
  end
end
