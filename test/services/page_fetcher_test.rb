require "test_helper"

class PageFetcherTest < ActiveSupport::TestCase
  PAGE_URL = "https://example.com/article"

  test "#fetch should return the successful response body" do
    stub_request(:get, PAGE_URL).to_return(status: 200, body: "<html>Sample article</html>")

    result = PageFetcher.new.fetch(PAGE_URL)

    assert_equal "<html>Sample article</html>", result.body
    assert_nil result.failure
  end

  test "#fetch should preserve an empty successful response" do
    stub_request(:get, PAGE_URL).to_return(status: 204, body: "")

    result = PageFetcher.new.fetch(PAGE_URL)

    assert_equal "", result.body
    assert_nil result.failure
  end

  test "#fetch should skip blank URLs without requesting a page" do
    [nil, "", " "].each do |url|
      result = PageFetcher.new.fetch(url)
      assert_nil result.body
      assert_nil result.failure
    end

    assert_not_requested :get, /./
  end

  test "#fetch should return HTTP failure details without logging or reporting" do
    stub_request(:get, PAGE_URL).to_return(status: 503, body: "Service unavailable")
    warnings = []
    result = nil

    reports = capture_error_reports do
      Rails.logger.stub(:warn, ->(message) { warnings << message }) do
        result = PageFetcher.new.fetch(PAGE_URL)
      end
    end

    assert_nil result.body
    assert_equal({ url: PAGE_URL, status: 503, message: "HTTP 503", retryable: true }, result.failure)
    assert_empty warnings
    assert_empty reports
    assert_requested :get, PAGE_URL, times: 1
  end

  test "#fetch should return connection failure details without reporting" do
    stub_request(:get, PAGE_URL).to_raise(Faraday::ConnectionFailed.new("connection refused"))
    result = nil

    reports = capture_error_reports { result = PageFetcher.new.fetch(PAGE_URL) }

    assert_empty reports
    assert_nil result.body
    assert_equal "HttpClient::ConnectionError", result.failure[:error_class]
    assert result.failure[:retryable]
    assert_includes result.failure[:message], "connection refused"
    assert_equal PAGE_URL, result.failure[:url]
    assert_requested :get, PAGE_URL, times: 1
  end

  test "#fetch should return timeout details without reporting" do
    stub_request(:get, PAGE_URL).to_raise(Faraday::TimeoutError.new("request timed out"))
    result = nil

    reports = capture_error_reports { result = PageFetcher.new.fetch(PAGE_URL) }

    assert_empty reports
    assert_nil result.body
    assert_equal "HttpClient::TimeoutError", result.failure[:error_class]
    assert result.failure[:retryable]
    assert_requested :get, PAGE_URL, times: 1
  end

  test "#fetch should return TLS failure details without reporting" do
    stub_request(:get, PAGE_URL).to_raise(Faraday::SSLError.new("certificate verify failed"))
    result = nil

    reports = capture_error_reports { result = PageFetcher.new.fetch(PAGE_URL) }

    assert_empty reports
    assert_nil result.body
    assert_equal "HttpClient::SSLError", result.failure[:error_class]
    assert result.failure[:retryable]
    assert_equal PAGE_URL, result.failure[:url]
    assert_includes result.failure[:message], "certificate verify failed"
    assert_requested :get, PAGE_URL, times: 1
  end

  test "#fetch should treat redirect loops and blocked URLs as external failures" do
    [HttpClient::TooManyRedirectsError, HttpClient::BlockedUrlError].each do |error_class|
      stub_request(:get, PAGE_URL).to_raise(error_class.new("Page unavailable"))
      result = nil

      reports = capture_error_reports { result = PageFetcher.new.fetch(PAGE_URL) }

      assert_empty reports
      assert_nil result.body
      assert_equal({ url: PAGE_URL, error_class: error_class.name, message: "Page unavailable", retryable: false },
                   result.failure)
    end
  end

  test "#fetch should propagate unexpected errors without reporting them" do
    [HttpClient::Error, ArgumentError].each do |error_class|
      error = error_class.new("unexpected error")
      stub_request(:get, PAGE_URL).to_raise(error)

      reports = capture_error_reports do
        assert_same error, assert_raises(error_class) { PageFetcher.new.fetch(PAGE_URL) }
      end

      assert_empty reports
    end
  end

  test "#fetch should mark temporary HTTP failures as retryable" do
    [408, 429, 500, 503, 599].each do |status|
      stub_request(:get, PAGE_URL).to_return(status: status)

      assert PageFetcher.new.fetch(PAGE_URL).failure[:retryable], "HTTP #{status}"
    end
  end

  test "#fetch should not retry permanent HTTP failures" do
    [401, 403, 404, 410, 422].each do |status|
      stub_request(:get, PAGE_URL).to_return(status: status)

      assert_not PageFetcher.new.fetch(PAGE_URL).failure[:retryable], "HTTP #{status}"
    end
  end
end
