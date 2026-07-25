require "test_helper"

class FreefeedClientSubscriberStatisticsTest < ActiveSupport::TestCase
  setup do
    @host = "https://freefeed.net"
    @token = "test_token"
    @client = FreefeedClient.new(host: @host, token: @token)
  end

  test "returns subscriber count from user statistics" do
    stub_request(:get, "#{@host}/v2/users/test-group/statistics")
      .to_return(
        status: 200,
        body: { users: { username: "test-group" }, statistics: { subscribers: "42" } }.to_json
      )

    assert_equal 42, @client.subscribers_count("test-group")
  end

  test "escapes the username in the request path" do
    stub_request(:get, "#{@host}/v2/users/test%20group/statistics")
      .to_return(status: 200, body: { statistics: { subscribers: 1 } }.to_json)

    assert_equal 1, @client.subscribers_count("test group")
  end

  test "raises on malformed statistics response" do
    stub_request(:get, "#{@host}/v2/users/test-group/statistics")
      .to_return(status: 200, body: { users: { username: "test-group" } }.to_json)

    error = assert_raises(FreefeedClient::Error) do
      @client.subscribers_count("test-group")
    end

    assert_includes error.message, "Invalid user statistics response format"
  end

  test "preserves not found errors from the shared client" do
    stub_request(:get, "#{@host}/v2/users/missing/statistics")
      .to_return(status: 404, body: { err: "Account 'missing' was not found" }.to_json)

    error = assert_raises(FreefeedClient::NotFoundError) do
      @client.subscribers_count("missing")
    end

    assert_equal "Account 'missing' was not found", error.message
  end
end
