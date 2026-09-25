require "test_helper"

class Loader::ThrottledTest < ActiveSupport::TestCase
  test ".from_response should preserve the host, status and delay without the URL or body" do
    response = HttpClient::Response.new(status: 429, body: "private response",
                                        headers: { "Retry-After" => "120" },
                                        url: "https://example.com/private?token=secret")

    error = Loader::Throttled.from_response(response, source_host: "example.com")

    assert_equal({ source_host: "example.com", http_status: 429, retry_after: 120 }, error.details)
    assert_equal "Source is rate limiting requests; try again later", error.message
  end

  test ".from_response should accept an HTTP date" do
    freeze_time
    response = HttpClient::Response.new(status: 429, body: "", headers: { "retry-after" => 10.minutes.from_now.httpdate })

    error = Loader::Throttled.from_response(response, source_host: "example.com")

    assert_equal 600, error.retry_after
  end

  test ".from_response should use a cooldown when the header is absent" do
    response = HttpClient::Response.new(status: 429, body: "")

    error = Loader::Throttled.from_response(response, source_host: "example.com")

    assert_equal 300, error.retry_after
  end

  test ".from_response should reject a malformed delay" do
    response = HttpClient::Response.new(status: 429, body: "", headers: { "retry-after" => "120 seconds" })

    error = Loader::Throttled.from_response(response, source_host: "example.com")

    assert_equal 300, error.retry_after
  end

  test ".from_response should use a cooldown for a past HTTP date" do
    response = HttpClient::Response.new(status: 429, body: "", headers: { "retry-after" => 1.minute.ago.httpdate })

    error = Loader::Throttled.from_response(response, source_host: "example.com")

    assert_equal 300, error.retry_after
  end

  test ".from_response should avoid immediate retries for a zero delay" do
    response = HttpClient::Response.new(status: 429, body: "", headers: { "retry-after" => "0" })

    error = Loader::Throttled.from_response(response, source_host: "example.com")

    assert_equal 300, error.retry_after
  end
end
