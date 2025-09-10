require "test_helper"
require "lib/http_client/faraday_adapter"

class HttpClient::FaradayAdapterTest < ActiveSupport::TestCase
  setup do
    @client = HttpClient::FaradayAdapter.new(timeout: 5)
  end

  test "performs successful GET request" do
    stub_request(:get, "https://example.com/test")
      .with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: '{"success": true}', headers: { "Content-Type" => "application/json" })

    response = @client.get("https://example.com/test", headers: { "Accept" => "application/json" })

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

    response = @client.post(
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

    response = @client.put(
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

    response = @client.delete("https://example.com/test/1", headers: { "Authorization" => "Bearer token123" })

    assert_equal 204, response.status
    assert_equal "", response.body
    assert response.success?
  end

  test "handles HTTP error responses" do
    stub_request(:get, "https://example.com/error")
      .to_return(status: 404, body: "Not Found")

    response = @client.get("https://example.com/error")

    assert_equal 404, response.status
    assert_equal "Not Found", response.body
    assert_not response.success?
  end

  test "raises ConnectionError on connection failures" do
    stub_request(:get, "https://example.com/fail")
      .to_raise(Faraday::ConnectionFailed.new("Connection failed"))

    error = assert_raises(HttpClient::ConnectionError) do
      @client.get("https://example.com/fail")
    end

    assert_includes error.message, "Connection failed"
  end

  test "raises TimeoutError on request timeouts" do
    stub_request(:get, "https://example.com/timeout")
      .to_raise(Faraday::TimeoutError.new("Request timed out"))

    error = assert_raises(HttpClient::TimeoutError) do
      @client.get("https://example.com/timeout")
    end

    assert_includes error.message, "Request timed out"
  end

  test "raises Error on other Faraday errors" do
    stub_request(:get, "https://example.com/error")
      .to_raise(Faraday::Error.new("Generic error"))

    error = assert_raises(HttpClient::Error) do
      @client.get("https://example.com/error")
    end

    assert_includes error.message, "Generic error"
  end
end