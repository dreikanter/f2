require "test_helper"

class HttpClient::CachingTest < ActiveSupport::TestCase
  # Inner client that records how often each GET URL is hit and returns whatever
  # the supplied block produces. Non-GET verbs return a canned success.
  class RecordingClient < HttpClient::Base
    attr_reader :get_calls, :verb_calls

    def initialize(&get_handler)
      super()
      @get_handler = get_handler
      @get_calls = Hash.new(0)
      @verb_calls = Hash.new(0)
    end

    def get(url, headers: {}, options: {})
      @get_calls[url] += 1
      @get_handler.call(url)
    end

    def post(url, body: nil, headers: {}, options: {})
      @verb_calls[:post] += 1
      HttpClient::Response.new(status: 200, body: "ok")
    end

    def put(url, body: nil, headers: {}, options: {})
      @verb_calls[:put] += 1
      HttpClient::Response.new(status: 200, body: "ok")
    end

    def delete(url, headers: {}, options: {})
      @verb_calls[:delete] += 1
      HttpClient::Response.new(status: 200, body: "ok")
    end
  end

  def ok(body = "body", status: 200)
    HttpClient::Response.new(status: status, body: body)
  end

  test "#get should cache a successful response and reuse it for the same URL" do
    inner = RecordingClient.new { ok("hello") }
    client = HttpClient::Caching.new(inner)

    first = client.get("https://example.com/feed")
    second = client.get("https://example.com/feed")

    assert_equal "hello", first.body
    assert_same first, second
    assert_equal 1, inner.get_calls["https://example.com/feed"]
  end

  test "#get should cache each URL independently" do
    inner = RecordingClient.new { |url| ok(url) }
    client = HttpClient::Caching.new(inner)

    client.get("https://a.example/feed")
    client.get("https://b.example/feed")
    client.get("https://a.example/feed")

    assert_equal 1, inner.get_calls["https://a.example/feed"]
    assert_equal 1, inner.get_calls["https://b.example/feed"]
  end

  test "#get should not cache non-2xx responses" do
    inner = RecordingClient.new { ok("error", status: 500) }
    client = HttpClient::Caching.new(inner)

    client.get("https://example.com/down")
    client.get("https://example.com/down")

    assert_equal 2, inner.get_calls["https://example.com/down"]
  end

  test "#get should not cache when the inner client raises" do
    inner = RecordingClient.new { raise HttpClient::TimeoutError, "boom" }
    client = HttpClient::Caching.new(inner)

    assert_raises(HttpClient::TimeoutError) { client.get("https://example.com/slow") }
    assert_raises(HttpClient::TimeoutError) { client.get("https://example.com/slow") }

    assert_equal 2, inner.get_calls["https://example.com/slow"]
  end

  test "#get should serve from cache within the TTL window" do
    inner = RecordingClient.new { ok("hello") }
    client = HttpClient::Caching.new(inner, ttl: 60)
    clock = [1000.0]
    client.define_singleton_method(:monotonic_now) { clock[0] }

    client.get("https://example.com/feed")
    clock[0] += 59
    client.get("https://example.com/feed")

    assert_equal 1, inner.get_calls["https://example.com/feed"]
  end

  test "#get should re-fetch after the entry expires" do
    inner = RecordingClient.new { ok("hello") }
    client = HttpClient::Caching.new(inner, ttl: 60)
    clock = [1000.0]
    client.define_singleton_method(:monotonic_now) { clock[0] }

    client.get("https://example.com/feed")
    clock[0] += 61
    client.get("https://example.com/feed")

    assert_equal 2, inner.get_calls["https://example.com/feed"]
  end

  test "#post, #put and #delete should delegate without caching" do
    inner = RecordingClient.new { ok }
    client = HttpClient::Caching.new(inner)

    client.post("https://example.com/x")
    client.post("https://example.com/x")
    client.put("https://example.com/x")
    client.delete("https://example.com/x")

    assert_equal 2, inner.verb_calls[:post]
    assert_equal 1, inner.verb_calls[:put]
    assert_equal 1, inner.verb_calls[:delete]
  end
end
