require "test_helper"

class HttpClient::CachingAdapterTest < ActiveSupport::TestCase
  def setup
    @cache = {}
    @cache_store = FakeCacheStore.new(@cache)
    @base_client = HttpClient::FaradayAdapter.new(timeout: 5)
  end

  def cached_client(cache_expires_in: nil)
    options = { adapter: @base_client, cache_store: @cache_store }
    options[:cache_expires_in] = cache_expires_in if cache_expires_in
    HttpClient::CachingAdapter.new(**options)
  end

  test "caches GET requests" do
    client = cached_client

    stub_request(:get, "https://example.com/cached")
      .to_return(status: 200, body: "Original response")
      .times(1) # Should only be called once

    # First request - hits the server
    response1 = client.get("https://example.com/cached")
    assert_equal "Original response", response1.body

    # Second request - uses cache
    response2 = client.get("https://example.com/cached")
    assert_equal "Original response", response2.body
    assert_equal 1, @cache.size
  end

  test "does not cache POST requests" do
    client = cached_client

    stub_request(:post, "https://example.com/post")
      .with(body: "data")
      .to_return(status: 201, body: "Created")
      .times(2) # Should be called twice

    # Both requests hit the server
    client.post("https://example.com/post", body: "data")
    client.post("https://example.com/post", body: "data")

    assert_equal 0, @cache.size
  end

  test "does not cache PUT requests" do
    client = cached_client

    stub_request(:put, "https://example.com/put")
      .with(body: "data")
      .to_return(status: 200, body: "Updated")
      .times(2)

    client.put("https://example.com/put", body: "data")
    client.put("https://example.com/put", body: "data")

    assert_equal 0, @cache.size
  end

  test "does not cache DELETE requests" do
    client = cached_client

    stub_request(:delete, "https://example.com/delete")
      .to_return(status: 204)
      .times(2)

    client.delete("https://example.com/delete")
    client.delete("https://example.com/delete")

    assert_equal 0, @cache.size
  end

  test "different URLs produce different cache entries" do
    client = cached_client

    stub_request(:get, "https://example.com/page1")
      .to_return(status: 200, body: "Page 1")
      .times(1)

    stub_request(:get, "https://example.com/page2")
      .to_return(status: 200, body: "Page 2")
      .times(1)

    client.get("https://example.com/page1")
    client.get("https://example.com/page2")

    # Both URLs should be cached separately
    assert_equal 2, @cache.size
  end

  test "uses custom cache_expires_in" do
    client = cached_client(cache_expires_in: 3600)

    assert_equal 3600, client.cache_expires_in
  end

  test "uses default cache expiration if not specified" do
    client = cached_client

    assert_equal HttpClient::CachingAdapter::DEFAULT_CACHE_EXPIRATION, client.cache_expires_in
  end

  test "passes expires_in to cache store" do
    client = cached_client(cache_expires_in: 1800)

    stub_request(:get, "https://example.com/test")
      .to_return(status: 200, body: "Test")

    client.get("https://example.com/test")

    # Check that expires_in was passed to write
    cache_entry = @cache.values.first
    assert_equal 1800, cache_entry[:expires_in]
  end

  test "works with HttpClient.build factory" do
    client = HttpClient.build(cache_store: @cache_store, timeout: 10)

    assert_instance_of HttpClient::CachingAdapter, client
    assert_instance_of HttpClient::FaradayAdapter, client.adapter

    stub_request(:get, "https://example.com/factory")
      .to_return(status: 200, body: "Factory response")
      .times(1)

    response1 = client.get("https://example.com/factory")
    response2 = client.get("https://example.com/factory")

    assert_equal "Factory response", response1.body
    assert_equal "Factory response", response2.body
    assert_equal 1, @cache.size
  end

  test "build without cache_store returns unwrapped adapter" do
    client = HttpClient.build(timeout: 10)

    assert_instance_of HttpClient::FaradayAdapter, client
    assert_not_instance_of HttpClient::CachingAdapter, client
  end

  # Fake cache store compatible with ActiveSupport::Cache::Store interface
  class FakeCacheStore
    def initialize(storage)
      @storage = storage
    end

    def read(key)
      entry = @storage[key]
      return nil unless entry
      return nil if entry[:expires_at] && entry[:expires_at] < Time.current

      entry[:value]
    end

    def write(key, value, expires_in: nil)
      expires_at = expires_in ? Time.current + expires_in : nil
      @storage[key] = { value: value, expires_in: expires_in, expires_at: expires_at }
    end
  end
end
