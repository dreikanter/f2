require "test_helper"

class PageFetcherTest < ActiveSupport::TestCase
  include DnsTestHelper

  PAGE_URL = "https://example.com/article"

  test "#fetch should return the successful response body" do
    stub_request(:get, PAGE_URL).to_return(status: 200, body: "<html>Sample article</html>")

    stub_dns do
      assert_equal "<html>Sample article</html>", PageFetcher.new.fetch(PAGE_URL)
    end
  end

  test "#fetch should preserve an empty successful response" do
    stub_request(:get, PAGE_URL).to_return(status: 204, body: "")

    stub_dns do
      assert_equal "", PageFetcher.new.fetch(PAGE_URL)
    end
  end

  test "#fetch should skip blank URLs without requesting a page" do
    fetcher = PageFetcher.new

    assert_nil fetcher.fetch(nil)
    assert_nil fetcher.fetch("")
    assert_nil fetcher.fetch(" ")

    assert_not_requested :get, /./
  end

  test "#fetch should return nil for an HTTP failure" do
    stub_request(:get, PAGE_URL).to_return(status: 503)

    assert_nil stub_dns { PageFetcher.new.fetch(PAGE_URL) }
    assert_requested :get, PAGE_URL, times: 1
  end

  test "#fetch should report network failures with context and return nil" do
    stub_request(:get, PAGE_URL).to_raise(Faraday::ConnectionFailed.new("connection refused"))
    context = { source: "sample" }
    reported = []

    Rails.error.stub(:report, ->(error, **options) { reported << [error, options] }) do
      assert_nil stub_dns { PageFetcher.new(context: context).fetch(PAGE_URL) }
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

    stub_dns do
      assert_raises(ArgumentError) { PageFetcher.new.fetch(PAGE_URL) }
    end
  end

  test "#fetch should reject a private URL without making a request" do
    assert_nil PageFetcher.new.fetch("http://169.254.169.254/latest/meta-data/")

    assert_not_requested :get, /./
  end

  test "#fetch should reject a hostname resolving to a private address" do
    stub_dns("example.com" => "10.0.0.1") do
      assert_nil PageFetcher.new.fetch(PAGE_URL)
    end

    assert_not_requested :get, /./
  end

  test "#fetch should follow redirects between public hosts" do
    stub_request(:get, PAGE_URL)
      .to_return(status: 302, headers: { "Location" => "https://other.example.com/article" })
    stub_request(:get, "https://other.example.com/article").to_return(body: "Sample article")

    stub_dns do
      assert_equal "Sample article", PageFetcher.new.fetch(PAGE_URL)
    end
  end

  test "#fetch should reject a redirect to a private URL" do
    stub_request(:get, PAGE_URL)
      .to_return(status: 302, headers: { "Location" => "http://127.0.0.1/private" })

    stub_dns do
      assert_nil PageFetcher.new.fetch(PAGE_URL)
    end

    assert_requested :get, PAGE_URL
    assert_not_requested :get, "http://127.0.0.1/private"
  end

  test "#fetch should reject a redirect hostname resolving to a private address" do
    stub_request(:get, PAGE_URL)
      .to_return(status: 302, headers: { "Location" => "https://internal.example.com/article" })

    stub_dns("internal.example.com" => "10.0.0.1") do
      assert_nil PageFetcher.new.fetch(PAGE_URL)
    end

    assert_requested :get, PAGE_URL
    assert_not_requested :get, "https://internal.example.com/article"
  end
end
