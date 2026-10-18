require "test_helper"

class OptionalPageFetcherTest < ActiveSupport::TestCase
  PAGE_URL = "https://example.com/article"

  test "#fetch should return downloaded content" do
    stub_request(:get, PAGE_URL).to_return(body: "content")

    assert_equal "content", OptionalPageFetcher.new.fetch(PAGE_URL)
  end

  test "#fetch should notify the consumer once per failure and return nil" do
    stub_request(:get, PAGE_URL).to_return(status: 503)
    errors = []
    fetcher = OptionalPageFetcher.new(on_error: ->(error) { errors << error })

    2.times { assert_nil fetcher.fetch(PAGE_URL) }

    assert_equal 2, errors.size
    assert_equal({ url: PAGE_URL, status: 503 }, errors.first.details)
  end

  test "#fetch should keep expected network failures out of error tracking" do
    stub_request(:get, PAGE_URL).to_timeout
    errors = []

    reports = capture_error_reports do
      assert_nil OptionalPageFetcher.new(on_error: ->(error) { errors << error }).fetch(PAGE_URL)
    end

    assert_empty reports
    assert_kind_of HttpClient::TimeoutError, errors.sole.original_error
  end

  test "#fetch should report unexpected handled HTTP errors" do
    stub_request(:get, PAGE_URL).to_raise(HttpClient::TooManyRedirectsError.new("Too many redirects"))

    reports = capture_error_reports { assert_nil OptionalPageFetcher.new.fetch(PAGE_URL) }

    assert_equal 1, reports.size
  end
end
