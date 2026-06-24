require "test_helper"

class HttpClient::CachingAdapterTest < ActiveSupport::TestCase
  def client
    @client ||= HttpClient::CachingAdapter.new(timeout: 5, max_redirects: 5)
  end

  test "is selectable through HttpClient.build" do
    built = HttpClient.build(adapter: HttpClient::CachingAdapter)

    assert_instance_of HttpClient::CachingAdapter, built
    assert_kind_of HttpClient::FaradayAdapter, built
  end

  test "caches a successful GET and serves repeats from cache" do
    stub_request(:get, "https://example.com/feed")
      .to_return(status: 200, body: "feed body")

    first = client.get("https://example.com/feed")
    second = client.get("https://example.com/feed")

    assert_equal "feed body", first.body
    assert_same first, second
    assert_requested :get, "https://example.com/feed", times: 1
  end

  test "caches each URL independently" do
    stub_request(:get, "https://example.com/a").to_return(status: 200, body: "A")
    stub_request(:get, "https://example.com/b").to_return(status: 200, body: "B")

    assert_equal "A", client.get("https://example.com/a").body
    assert_equal "B", client.get("https://example.com/b").body
    assert_equal "A", client.get("https://example.com/a").body

    assert_requested :get, "https://example.com/a", times: 1
    assert_requested :get, "https://example.com/b", times: 1
  end

  test "keys the cache by request headers" do
    stub_request(:get, "https://example.com/feed")
      .to_return(status: 200, body: "anon").then
      .to_return(status: 200, body: "with-ua")

    anon = client.get("https://example.com/feed")
    with_ua = client.get("https://example.com/feed", headers: { "User-Agent" => "x" })

    assert_equal "anon", anon.body
    assert_equal "with-ua", with_ua.body
    assert_requested :get, "https://example.com/feed", times: 2
  end

  test "does not cache non-2xx responses" do
    stub_request(:get, "https://example.com/flaky")
      .to_return(status: 404, body: "missing").then
      .to_return(status: 200, body: "recovered")

    first = client.get("https://example.com/flaky")
    second = client.get("https://example.com/flaky")

    assert_equal 404, first.status
    assert_equal 200, second.status
    assert_equal "recovered", second.body
    assert_requested :get, "https://example.com/flaky", times: 2
  end

  test "does not cache raised errors" do
    stub_request(:get, "https://example.com/blip")
      .to_raise(SocketError.new("getaddrinfo failed")).then
      .to_return(status: 200, body: "back online")

    assert_raises(HttpClient::ConnectionError) { client.get("https://example.com/blip") }

    recovered = client.get("https://example.com/blip")

    assert_equal 200, recovered.status
    assert_equal "back online", recovered.body
  end

  test "re-fetches after the cache entry expires" do
    expiring = HttpClient::CachingAdapter.new(cache_ttl: 0)

    stub_request(:get, "https://example.com/feed")
      .to_return(status: 200, body: "first").then
      .to_return(status: 200, body: "second")

    assert_equal "first", expiring.get("https://example.com/feed").body
    assert_equal "second", expiring.get("https://example.com/feed").body
    assert_requested :get, "https://example.com/feed", times: 2
  end

  test "does not cache POST requests" do
    stub_request(:post, "https://example.com/submit")
      .to_return(status: 200, body: "one").then
      .to_return(status: 200, body: "two")

    assert_equal "one", client.post("https://example.com/submit").body
    assert_equal "two", client.post("https://example.com/submit").body
  end

  test "still follows redirects like the Faraday adapter" do
    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "https://example.com/final" })
    stub_request(:get, "https://example.com/final")
      .to_return(status: 200, body: "final destination")

    response = client.get("https://example.com/redirect")

    assert_equal 200, response.status
    assert_equal "final destination", response.body
  end
end
