require "test_helper"

class FreefeedClientTest < ActiveSupport::TestCase
  def setup
    @host = "https://freefeed.net"
    @token = "test_token_123"
    @client = FreefeedClient.new(host: @host, token: @token)
  end

  # Constructor tests
  test "initializes with required parameters" do
    client = FreefeedClient.new(host: @host, token: @token)
    assert_equal "https://freefeed.net", client.host
    assert_instance_of HttpClient::FaradayAdapter, client.http_client
  end

  test "initializes with custom http_client" do
    custom_client = HttpClient::FaradayAdapter.new(timeout: 60)
    client = FreefeedClient.new(host: @host, token: @token, http_client: custom_client)
    assert_equal custom_client, client.http_client
  end

  test "strips trailing slash from host" do
    client = FreefeedClient.new(host: "https://freefeed.net/", token: @token)
    assert_equal "https://freefeed.net", client.host
  end

  # whoami method tests
  test "whoami returns user data on success" do
    response_body = {
      "users" => {
        "id" => "user123",
        "username" => "testuser",
        "screenName" => "Test User",
        "email" => "test@example.com"
      }
    }.to_json

    stub_request(:get, "#{@host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => "Bearer #{@token}",
          "Accept" => "application/json"
        }
      )
      .to_return(status: 200, body: response_body)

    result = @client.whoami

    assert_equal "user123", result[:id]
    assert_equal "testuser", result[:username]
    assert_equal "Test User", result[:screen_name]
    assert_equal "test@example.com", result[:email]
  end

  test "whoami raises UnauthorizedError on 401" do
    stub_request(:get, "#{@host}/v4/users/whoami")
      .to_return(status: 401, body: "Unauthorized")

    assert_raises(FreefeedClient::UnauthorizedError) do
      @client.whoami
    end
  end

  test "whoami raises UnauthorizedError on 403" do
    stub_request(:get, "#{@host}/v4/users/whoami")
      .to_return(status: 403, body: "Forbidden")

    assert_raises(FreefeedClient::UnauthorizedError) do
      @client.whoami
    end
  end

  test "whoami raises NotFoundError on 404" do
    stub_request(:get, "#{@host}/v4/users/whoami")
      .to_return(status: 404, body: "Not Found")

    assert_raises(FreefeedClient::NotFoundError) do
      @client.whoami
    end
  end

  test "whoami raises Error on other HTTP errors" do
    stub_request(:get, "#{@host}/v4/users/whoami")
      .to_return(status: 500, body: "Internal Server Error")

    error = assert_raises(FreefeedClient::Error) do
      @client.whoami
    end
    assert_includes error.message, "HTTP 500"
  end

  test "whoami raises Error on invalid JSON" do
    stub_request(:get, "#{@host}/v4/users/whoami")
      .to_return(status: 200, body: "invalid json")

    error = assert_raises(FreefeedClient::Error) do
      @client.whoami
    end
    assert_includes error.message, "Invalid JSON response"
  end

  test "whoami raises Error on invalid response format" do
    stub_request(:get, "#{@host}/v4/users/whoami")
      .to_return(status: 200, body: '{"invalid": "format"}')

    error = assert_raises(FreefeedClient::Error) do
      @client.whoami
    end
    assert_includes error.message, "Invalid whoami response format"
  end

  test "whoami raises Error on HTTP client errors" do
    stub_request(:get, "#{@host}/v4/users/whoami")
      .to_raise(HttpClient::TimeoutError.new("Connection timeout"))

    error = assert_raises(FreefeedClient::Error) do
      @client.whoami
    end
    assert_includes error.message, "Failed to validate token"
    assert_includes error.message, "Connection timeout"
  end

  # managed_groups method tests
  test "managed_groups returns groups data on success" do
    response_body = [
      {
        "id" => "group1",
        "username" => "testgroup",
        "screenName" => "Test Group",
        "isPrivate" => "0",
        "isRestricted" => "1"
      },
      {
        "id" => "group2",
        "username" => "privategroup",
        "screenName" => "Private Group",
        "isPrivate" => "1",
        "isRestricted" => "0"
      }
    ].to_json

    stub_request(:get, "#{@host}/v4/managedGroups")
      .with(
        headers: {
          "Authorization" => "Bearer #{@token}",
          "Accept" => "application/json"
        }
      )
      .to_return(status: 200, body: response_body)

    result = @client.managed_groups

    assert_equal 2, result.length

    first_group = result[0]
    assert_equal "group1", first_group[:id]
    assert_equal "testgroup", first_group[:username]
    assert_equal "Test Group", first_group[:screen_name]
    assert_equal false, first_group[:is_private]
    assert_equal true, first_group[:is_restricted]

    second_group = result[1]
    assert_equal "group2", second_group[:id]
    assert_equal "privategroup", second_group[:username]
    assert_equal "Private Group", second_group[:screen_name]
    assert_equal true, second_group[:is_private]
    assert_equal false, second_group[:is_restricted]
  end

  test "managed_groups raises UnauthorizedError on 401" do
    stub_request(:get, "#{@host}/v4/managedGroups")
      .to_return(status: 401, body: "Unauthorized")

    assert_raises(FreefeedClient::UnauthorizedError) do
      @client.managed_groups
    end
  end

  test "managed_groups raises Error on invalid JSON" do
    stub_request(:get, "#{@host}/v4/managedGroups")
      .to_return(status: 200, body: "invalid json")

    error = assert_raises(FreefeedClient::Error) do
      @client.managed_groups
    end
    assert_includes error.message, "Invalid JSON response"
  end

  test "managed_groups raises Error on non-array response" do
    stub_request(:get, "#{@host}/v4/managedGroups")
      .to_return(status: 200, body: '{"invalid": "format"}')

    error = assert_raises(FreefeedClient::Error) do
      @client.managed_groups
    end
    assert_includes error.message, "Invalid managed groups response format"
  end

  test "managed_groups raises Error on HTTP client errors" do
    stub_request(:get, "#{@host}/v4/managedGroups")
      .to_raise(HttpClient::ConnectionError.new("Connection failed"))

    error = assert_raises(FreefeedClient::Error) do
      @client.managed_groups
    end
    assert_includes error.message, "Failed to fetch managed groups"
    assert_includes error.message, "Connection failed"
  end

  # Edge cases
  test "handles empty managed groups response" do
    stub_request(:get, "#{@host}/v4/managedGroups")
      .to_return(status: 200, body: "[]")

    result = @client.managed_groups
    assert_equal [], result
  end

  test "handles missing optional user fields in whoami" do
    response_body = {
      "users" => {
        "id" => "user123",
        "username" => "testuser"
      }
    }.to_json

    stub_request(:get, "#{@host}/v4/users/whoami")
      .to_return(status: 200, body: response_body)

    result = @client.whoami

    assert_equal "user123", result[:id]
    assert_equal "testuser", result[:username]
    assert_nil result[:screen_name]
    assert_nil result[:email]
  end

  test "handles missing optional group fields" do
    response_body = [
      {
        "id" => "group1",
        "username" => "testgroup"
      }
    ].to_json

    stub_request(:get, "#{@host}/v4/managedGroups")
      .to_return(status: 200, body: response_body)

    result = @client.managed_groups

    group = result[0]
    assert_equal "group1", group[:id]
    assert_equal "testgroup", group[:username]
    assert_nil group[:screen_name]
    assert_equal false, group[:is_private]  # Default when field is missing
    assert_equal false, group[:is_restricted]  # Default when field is missing
  end
end
