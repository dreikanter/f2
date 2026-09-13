require "test_helper"

class HttpClient::FaradayAdapterTest < ActiveSupport::TestCase
  def client
    @client ||= HttpClient::FaradayAdapter.new(timeout: 5, follow_redirects: true, max_redirects: 5)
  end

  test "#get should perform a successful GET request" do
    stub_request(:get, "https://example.com/test")
      .with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: '{"success": true}', headers: { "Content-Type" => "application/json" })

    response = client.get("https://example.com/test", headers: { "Accept" => "application/json" })

    assert_equal 200, response.status
    assert_equal '{"success": true}', response.body
    assert response.success?
  end

  test "#post should perform a successful POST request" do
    stub_request(:post, "https://example.com/test")
      .with(
        body: '{"data": "test"}',
        headers: { "Content-Type" => "application/json" }
      )
      .to_return(status: 201, body: '{"created": true}')

    response = client.post(
      "https://example.com/test",
      body: '{"data": "test"}',
      headers: { "Content-Type" => "application/json" }
    )

    assert_equal 201, response.status
    assert_equal '{"created": true}', response.body
    assert response.success?
  end

  test "#put should perform a successful PUT request" do
    stub_request(:put, "https://example.com/test/1")
      .with(
        body: '{"data": "updated"}',
        headers: { "Content-Type" => "application/json" }
      )
      .to_return(status: 200, body: '{"updated": true}')

    response = client.put(
      "https://example.com/test/1",
      body: '{"data": "updated"}',
      headers: { "Content-Type" => "application/json" }
    )

    assert_equal 200, response.status
    assert_equal '{"updated": true}', response.body
    assert response.success?
  end

  test "#delete should perform a successful DELETE request" do
    stub_request(:delete, "https://example.com/test/1")
      .with(headers: { "Authorization" => "Bearer token123" })
      .to_return(status: 204, body: "")

    response = client.delete("https://example.com/test/1", headers: { "Authorization" => "Bearer token123" })

    assert_equal 204, response.status
    assert_equal "", response.body
    assert response.success?
  end

  test "#get should handle HTTP error responses" do
    stub_request(:get, "https://example.com/error")
      .to_return(status: 404, body: "Not Found")

    response = client.get("https://example.com/error")

    assert_equal 404, response.status
    assert_equal "Not Found", response.body
    assert_not response.success?
  end

  test "#get should raise ConnectionError on connection failures" do
    stub_request(:get, "https://example.com/fail")
      .to_raise(SocketError.new("getaddrinfo: Name or service not known"))

    error = assert_raises(HttpClient::ConnectionError) do
      client.get("https://example.com/fail")
    end

    assert_includes error.message, "Connection failed"
  end

  test "#get should raise TimeoutError on request timeouts" do
    stub_request(:get, "https://example.com/timeout")
      .to_raise(Timeout::Error.new("execution expired"))

    error = assert_raises(HttpClient::TimeoutError) do
      client.get("https://example.com/timeout")
    end

    assert_includes error.message, "Request timed out"
  end

  test "#get should raise ConnectionError on network errors" do
    stub_request(:get, "https://example.com/network-error")
      .to_raise(Errno::ECONNREFUSED)

    error = assert_raises(HttpClient::ConnectionError) do
      client.get("https://example.com/network-error")
    end

    assert_includes error.message, "Connection failed"
  end

  test "#get should follow redirects by default" do
    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "https://example.com/final" })

    stub_request(:get, "https://example.com/final")
      .to_return(status: 200, body: "Final destination")

    response = client.get("https://example.com/redirect")

    assert_equal 200, response.status
    assert_equal "Final destination", response.body
    assert response.success?
  end

  test "#get should expose the requested URL on the response" do
    stub_request(:get, "https://example.com/test")
      .to_return(status: 200, body: "ok")

    response = client.get("https://example.com/test")

    assert_equal "https://example.com/test", response.url
  end

  test "#get should expose the final URL after redirects" do
    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "https://blog.example.com/final" })

    stub_request(:get, "https://blog.example.com/final")
      .to_return(status: 200, body: "Final destination")

    response = client.get("https://example.com/redirect")

    assert_equal "https://blog.example.com/final", response.url
  end

  test "#get should not follow redirects when explicitly disabled" do
    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "https://example.com/final" })

    response = client.get("https://example.com/redirect", options: { follow_redirects: false })

    assert_equal 302, response.status
    assert_not response.success?
  end

  test "#post should follow redirects when enabled" do
    stub_request(:post, "https://example.com/redirect")
      .with(body: '{"data": "test"}')
      .to_return(status: 307, headers: { "Location" => "https://example.com/final" })

    stub_request(:post, "https://example.com/final")
      .with(body: '{"data": "test"}')
      .to_return(status: 201, body: '{"created": true}')

    response = client.post("https://example.com/redirect", body: '{"data": "test"}')

    assert_equal 201, response.status
    assert_equal '{"created": true}', response.body
    assert response.success?
  end

  test "#post should not follow redirects when explicitly disabled" do
    stub_request(:post, "https://example.com/redirect")
      .with(body: '{"data": "test"}')
      .to_return(status: 307, headers: { "Location" => "https://example.com/final" })

    response = client.post("https://example.com/redirect", body: '{"data": "test"}', options: { follow_redirects: false })

    assert_equal 307, response.status
    assert_not response.success?
  end

  test "#get should handle multiple redirects" do
    stub_request(:get, "https://example.com/redirect1")
      .to_return(status: 301, headers: { "Location" => "https://example.com/redirect2" })

    stub_request(:get, "https://example.com/redirect2")
      .to_return(status: 302, headers: { "Location" => "https://example.com/final" })

    stub_request(:get, "https://example.com/final")
      .to_return(status: 200, body: "Final destination after multiple redirects")

    response = client.get("https://example.com/redirect1")

    assert_equal 200, response.status
    assert_equal "Final destination after multiple redirects", response.body
    assert response.success?
  end

  test "#get should raise TooManyRedirectsError when the limit is exceeded" do
    stub_request(:get, "https://example.com/redirect1")
      .to_return(status: 301, headers: { "Location" => "https://example.com/redirect2" })

    stub_request(:get, "https://example.com/redirect2")
      .to_return(status: 302, headers: { "Location" => "https://example.com/redirect3" })

    stub_request(:get, "https://example.com/redirect3")
      .to_return(status: 301, headers: { "Location" => "https://example.com/final" })

    stub_request(:get, "https://example.com/final")
      .to_return(status: 200, body: "Final destination")

    # With max_redirects: 2, should raise TooManyRedirectsError
    error = assert_raises(HttpClient::TooManyRedirectsError) do
      client.get("https://example.com/redirect1", options: { max_redirects: 2 })
    end

    assert_includes error.message, "too many redirects"
  end

  test "#post should enforce max_redirects" do
    # Test POST with redirect limit
    stub_request(:post, "https://example.com/redirect1")
      .with(body: "test data")
      .to_return(status: 307, headers: { "Location" => "https://example.com/redirect2" })

    stub_request(:post, "https://example.com/redirect2")
      .with(body: "test data")
      .to_return(status: 307, headers: { "Location" => "https://example.com/final" })

    stub_request(:post, "https://example.com/final")
      .with(body: "test data")
      .to_return(status: 200, body: "Success")

    # With max_redirects: 1, should raise TooManyRedirectsError
    assert_raises(HttpClient::TooManyRedirectsError) do
      client.post("https://example.com/redirect1", body: "test data", options: { max_redirects: 1 })
    end
  end

  test "#get should ignore max_redirects when follow_redirects is disabled" do
    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "https://example.com/final" })

    # max_redirects should be ignored when follow_redirects is false
    response = client.get("https://example.com/redirect", options: { follow_redirects: false, max_redirects: 10 })
    assert_equal 302, response.status
    assert_not response.success?
  end

  test "#initialize should set the default timeout" do
    custom_client = HttpClient::FaradayAdapter.new(timeout: 10)
    assert_equal 10, custom_client.options[:timeout]
  end

  test "#initialize should set the default follow_redirects" do
    custom_client = HttpClient::FaradayAdapter.new(follow_redirects: false)
    assert_not custom_client.options[:follow_redirects]
  end

  test "#initialize should set the default max_redirects" do
    custom_client = HttpClient::FaradayAdapter.new(max_redirects: 10)
    assert_equal 10, custom_client.options[:max_redirects]
  end

  test "#get should use constructor defaults when there are no per-request overrides" do
    custom_client = HttpClient::FaradayAdapter.new(follow_redirects: false)

    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "https://example.com/final" })

    # Should not follow redirect (constructor default is false)
    response = custom_client.get("https://example.com/redirect")
    assert_equal 302, response.status
    assert_not response.success?
  end

  test "#get should let per-request options override constructor defaults" do
    # Constructor sets follow_redirects: false
    custom_client = HttpClient::FaradayAdapter.new(follow_redirects: false)

    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "https://example.com/final" })

    stub_request(:get, "https://example.com/final")
      .to_return(status: 200, body: "Final destination")

    # Per-request override enables redirects
    response = custom_client.get("https://example.com/redirect", options: { follow_redirects: true })
    assert_equal 200, response.status
    assert_equal "Final destination", response.body
    assert response.success?
  end

  test "#get should accept a per-request timeout override" do
    # This test verifies the parameter is accepted and passed through correctly
    # The actual timeout behavior is tested by the timeout exception tests
    custom_client = HttpClient::FaradayAdapter.new(timeout: 30)

    stub_request(:get, "https://example.com/test")
      .to_return(status: 200, body: "Success")

    # Should work with per-request timeout override
    response = custom_client.get("https://example.com/test", options: { timeout: 60 })
    assert_equal 200, response.status
    assert_equal "Success", response.body
    assert response.success?
  end

  # --- public-only mode (SSRF redirect guard) ---

  def public_only
    { validate_url: PublicUrl.method(:safe?) }
  end

  test "#get should reject private DNS targets before making a pinned public request" do
    Socket.stub(:getaddrinfo, [[nil, nil, nil, "127.0.0.1"]]) do
      assert_raises(HttpClient::BlockedUrlError) do
        client.get("https://controlled.example/", options: public_only.merge(pin_public_address: true))
      end
    end
    assert_not_requested :get, "https://controlled.example/"
  end

  test "#get should validate each redirect hostname's DNS target for pinned public requests" do
    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "https://controlled.example/secret" })
    resolver = ->(host, *) { [[nil, nil, nil, host == "example.com" ? "93.184.216.34" : "169.254.169.254"]] }

    Socket.stub(:getaddrinfo, resolver) do
      assert_raises(HttpClient::BlockedUrlError) do
        client.get("https://example.com/redirect", options: public_only.merge(pin_public_address: true))
      end
    end
    assert_not_requested :get, "https://controlled.example/secret"
  end

  test "#get should retain the TLS hostname while pinning the socket and bypassing proxies" do
    stub_request(:get, "https://example.com/page").to_return(body: "ok")
    connections = []
    constructor = Net::HTTP.method(:new)
    factory = ->(*args) { constructor.call(*args).tap { |http| connections << http } }
    resolutions = 0
    resolver = lambda do |*|
      resolutions += 1
      [[nil, nil, nil, resolutions == 1 ? "93.184.216.34" : "127.0.0.1"]]
    end

    Net::HTTP.stub(:new, factory) do
      Socket.stub(:getaddrinfo, resolver) do
        response = client.get("https://example.com/page", options: public_only.merge(pin_public_address: true))
        assert_equal "ok", response.body
      end
    end

    assert_equal 1, resolutions
    http = connections.sole
    assert_equal "93.184.216.34", http.ipaddr
    assert_equal "example.com", http.address
    assert http.use_ssl?
    assert_equal OpenSSL::SSL::VERIFY_PEER, http.verify_mode
    assert_not http.proxy?
  end

  test "#get should block a non-public initial URL before any request in public-only mode" do
    error = assert_raises(HttpClient::BlockedUrlError) do
      client.get("http://127.0.0.1/secret", options: public_only)
    end

    assert_match(/non-public/i, error.message)
    assert_not_requested :get, "http://127.0.0.1/secret"
  end

  test "#get should block a redirect to a private address without fetching it in public-only mode" do
    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "http://127.0.0.1/metadata" })

    assert_raises(HttpClient::BlockedUrlError) do
      client.get("https://example.com/redirect", options: public_only)
    end

    assert_not_requested :get, "http://127.0.0.1/metadata"
  end

  test "#get should allow a redirect between public hosts in public-only mode" do
    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "https://example.org/final" })
    stub_request(:get, "https://example.org/final")
      .to_return(status: 200, body: "ok")

    response = client.get("https://example.com/redirect", options: public_only)

    assert_equal 200, response.status
    assert_equal "ok", response.body
  end

  test "#get should skip initial URL validation without public-only mode" do
    stub_request(:get, "http://127.0.0.1/allowed").to_return(status: 200, body: "ok")

    response = client.get("http://127.0.0.1/allowed")

    assert_equal 200, response.status
  end

  test "#get should block a private hop at the end of a public chain in public-only mode" do
    stub_request(:get, "https://a.example/1")
      .to_return(status: 302, headers: { "Location" => "https://b.example/2" })
    stub_request(:get, "https://b.example/2")
      .to_return(status: 302, headers: { "Location" => "http://127.0.0.1/secret" })

    assert_raises(HttpClient::BlockedUrlError) do
      client.get("https://a.example/1", options: public_only)
    end

    assert_not_requested :get, "http://127.0.0.1/secret"
  end

  test "#get should block a redirect to the cloud metadata address in public-only mode" do
    stub_request(:get, "https://example.com/go")
      .to_return(status: 302, headers: { "Location" => "http://169.254.169.254/latest/meta-data/" })

    assert_raises(HttpClient::BlockedUrlError) do
      client.get("https://example.com/go", options: public_only)
    end

    assert_not_requested :get, "http://169.254.169.254/latest/meta-data/"
  end

  test "#get should block a redirect to a decimal-encoded private address in public-only mode" do
    # 2130706433 == 127.0.0.1; the guard canonicalizes it the way the socket would.
    stub_request(:get, "https://example.com/go")
      .to_return(status: 302, headers: { "Location" => "http://2130706433/" })

    assert_raises(HttpClient::BlockedUrlError) do
      client.get("https://example.com/go", options: public_only)
    end

    assert_not_requested :get, "http://2130706433/"
  end
end
