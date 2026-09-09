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

  test "#fetch should warn with context and return nil for an HTTP failure" do
    stub_request(:get, PAGE_URL).to_return(status: 503, body: "Service unavailable")
    warnings = []

    Rails.logger.stub(:warn, ->(message) { warnings << message }) do
      assert_nil PageFetcher.new(context: { source: "sample" }).fetch(PAGE_URL)
    end

    assert_equal 1, warnings.size
    assert_includes warnings.first, "HTTP 503"
    assert_includes warnings.first, "source=sample"
    assert_includes warnings.first, "url=#{PAGE_URL}"
    assert_requested :get, PAGE_URL, times: 1
  end

  test "#fetch should report network failures with context and return nil" do
    stub_request(:get, PAGE_URL).to_raise(Faraday::ConnectionFailed.new("connection refused"))
    context = { source: "sample" }
    reported = []

    Rails.error.stub(:report, ->(error, **options) { reported << [error, options] }) do
      assert_nil PageFetcher.new(context: context).fetch(PAGE_URL)
    end

    assert_equal 1, reported.size
    error, options = reported.first
    assert_kind_of HttpClient::ConnectionError, error
    assert_equal :warning, options[:severity]
    assert_equal({ source: "sample", url: PAGE_URL }, options[:context])
    assert_requested :get, PAGE_URL, times: 1
  end

  test "#fetch should let unexpected errors propagate" do
    stub_request(:get, PAGE_URL).to_raise(ArgumentError.new("unexpected error"))

    assert_raises(ArgumentError) { PageFetcher.new.fetch(PAGE_URL) }
  end
end
