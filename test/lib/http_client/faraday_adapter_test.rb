require "test_helper"

class HttpClient::FaradayAdapterTest < ActiveSupport::TestCase
  def client
    client ||= HttpClient::FaradayAdapter.new(timeout: 5)
  end

  test "performs successful GET request" do
    stub_request(:get, "https://example.com/test")
      .with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: '{"success": true}', headers: { "Content-Type" => "application/json" })

    response = client.get("https://example.com/test", headers: { "Accept" => "application/json" })

    assert_equal 200, response.status
    assert_equal '{"success": true}', response.body
    assert response.success?
  end

  test "performs successful POST request" do
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

  test "performs successful PUT request" do
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

  test "performs successful DELETE request" do
    stub_request(:delete, "https://example.com/test/1")
      .with(headers: { "Authorization" => "Bearer token123" })
      .to_return(status: 204, body: "")

    response = client.delete("https://example.com/test/1", headers: { "Authorization" => "Bearer token123" })

    assert_equal 204, response.status
    assert_equal "", response.body
    assert response.success?
  end

  test "handles HTTP error responses" do
    stub_request(:get, "https://example.com/error")
      .to_return(status: 404, body: "Not Found")

    response = client.get("https://example.com/error")

    assert_equal 404, response.status
    assert_equal "Not Found", response.body
    assert_not response.success?
  end

  test "raises ConnectionError on connection failures" do
    stub_request(:get, "https://example.com/fail")
      .to_raise(SocketError.new("getaddrinfo: Name or service not known"))

    error = assert_raises(HttpClient::ConnectionError) do
      client.get("https://example.com/fail")
    end

    assert_includes error.message, "Connection failed"
  end

  test "raises TimeoutError on request timeouts" do
    stub_request(:get, "https://example.com/timeout")
      .to_raise(Timeout::Error.new("execution expired"))

    error = assert_raises(HttpClient::TimeoutError) do
      client.get("https://example.com/timeout")
    end

    assert_includes error.message, "Request timed out"
  end

  test "raises ConnectionError on network errors" do
    stub_request(:get, "https://example.com/network-error")
      .to_raise(Errno::ECONNREFUSED)

    error = assert_raises(HttpClient::ConnectionError) do
      client.get("https://example.com/network-error")
    end

    assert_includes error.message, "Connection failed"
  end

  test "follows redirects by default" do
    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "https://example.com/final" })
    
    stub_request(:get, "https://example.com/final")
      .to_return(status: 200, body: "Final destination")

    response = client.get("https://example.com/redirect")

    assert_equal 200, response.status
    assert_equal "Final destination", response.body
    assert response.success?
  end

  test "does not follow redirects when explicitly disabled" do
    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "https://example.com/final" })

    response = client.get("https://example.com/redirect", follow_redirects: false)

    assert_equal 302, response.status
    assert_not response.success?
  end

  test "follows redirects on POST requests when enabled" do
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

  test "does not follow redirects on POST when explicitly disabled" do
    stub_request(:post, "https://example.com/redirect")
      .with(body: '{"data": "test"}')
      .to_return(status: 307, headers: { "Location" => "https://example.com/final" })

    response = client.post("https://example.com/redirect", body: '{"data": "test"}', follow_redirects: false)

    assert_equal 307, response.status
    assert_not response.success?
  end

  test "handles multiple redirects" do
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

  test "raises TooManyRedirectsError when limit exceeded" do
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
      client.get("https://example.com/redirect1", max_redirects: 2)
    end

    assert_includes error.message, "too many redirects"
  end

  test "max_redirects applies to all HTTP methods" do
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
      client.post("https://example.com/redirect1", body: "test data", max_redirects: 1)
    end
  end

  test "max_redirects with follow_redirects disabled is ignored" do
    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "https://example.com/final" })

    # max_redirects should be ignored when follow_redirects is false
    response = client.get("https://example.com/redirect", follow_redirects: false, max_redirects: 10)
    assert_equal 302, response.status
    assert_not response.success?
  end
end
