require "test_helper"

class PageFetcherTest < ActiveSupport::TestCase
  PAGE_URL = "https://example.com/article"

  test "#fetch should return successful response bodies including empty ones" do
    ["<html>Sample article</html>", ""].each do |body|
      stub_request(:get, PAGE_URL).to_return(status: 200, body: body)
      assert_equal body, PageFetcher.new.fetch(PAGE_URL)
    end
  end

  test "#fetch should skip blank URLs" do
    [nil, "", " "].each { |url| assert_nil PageFetcher.new.fetch(url) }

    assert_not_requested :get, /./
  end

  test "#fetch should raise HTTP failure details without tracking them" do
    stub_request(:get, PAGE_URL).to_return(status: 503)

    assert_no_difference "Event.count" do
      error = assert_raises(PageFetcher::Error) { PageFetcher.new.fetch(PAGE_URL) }
      assert_equal({ url: PAGE_URL, status: 503 }, error.details)
      assert_equal "HTTP 503", error.message
    end
  end

  test "#fetch should preserve network error details and cause" do
    stub_request(:get, PAGE_URL).to_raise(Faraday::ConnectionFailed.new("connection refused"))

    reports = capture_error_reports do
      error = assert_raises(PageFetcher::Error) { PageFetcher.new.fetch(PAGE_URL) }
      assert_equal PAGE_URL, error.url
      assert_kind_of HttpClient::ConnectionError, error.original_error
      assert_same error.original_error, error.cause
      assert_includes error.message, "connection refused"
    end

    assert_empty reports
  end

  test "#fetch should let unexpected errors propagate" do
    stub_request(:get, PAGE_URL).to_raise(ArgumentError.new("unexpected error"))

    assert_raises(ArgumentError) { PageFetcher.new.fetch(PAGE_URL) }
  end
end
