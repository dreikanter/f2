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

  test "#fetch should report unexpected HTTP client errors with context and return nil" do
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

  test "#fetch should create one immutable warning per failed download" do
    feed = create(:feed)
    event = create(:event, type: "feed_refresh", subject: feed, user: feed.user)
    original_metadata = event.metadata.deep_dup
    fetcher = PageFetcher.new(event: event, context: { uid: "entry-1" })
    stub_request(:get, PAGE_URL).to_return(status: 503)

    2.times { assert_nil fetcher.fetch(PAGE_URL) }

    failures = event.references
    assert_equal 2, failures.size
    assert failures.all?(&:warning?)
    assert failures.all? { |failure| failure.type == "page_download_failed" }
    assert_equal original_metadata, event.reload.metadata
    assert_equal({ "uid" => "entry-1", "url" => PAGE_URL, "status" => 503 }, failures.first.metadata["stats"])
    assert_equal feed.user, failures.first.user
  end

  test "#fetch should record timeouts without reporting expected network failures" do
    feed = create(:feed)
    stub_request(:get, PAGE_URL).to_timeout

    reports = capture_error_reports do
      assert_nil PageFetcher.new(subject: feed).fetch(PAGE_URL)
    end

    assert_empty reports
    failure = feed.events.where(type: "page_download_failed").sole
    assert_equal "HttpClient::TimeoutError", failure.metadata.dig("stats", "error_class")
  end
end
