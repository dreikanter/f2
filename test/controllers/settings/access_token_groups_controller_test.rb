require "test_helper"

class Settings::AccessTokenGroupsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def with_caching
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original_cache
  end

  test "index should find access token and fetch managed groups" do
    sign_in_as(user)

    response_body = [
      {
        "id" => "group1",
        "username" => "group1",
        "screenName" => "Group 1",
        "isPrivate" => "0",
        "isRestricted" => "0"
      },
      {
        "id" => "group2",
        "username" => "group2",
        "screenName" => "Group 2",
        "isPrivate" => "1",
        "isRestricted" => "0"
      }
    ].to_json

    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.token_value}",
          "Accept" => "application/json"
        }
      )
      .to_return(status: 200, body: response_body)

    get settings_access_token_groups_path(access_token), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "group1"
    assert_includes response.body, "Group 1"
    assert_includes response.body, "group2"
    assert_includes response.body, "Group 2"
    assert_includes response.body, "🔒"
  end

  test "index should handle FreefeedClient::Error and render error partial" do
    sign_in_as(user)

    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .to_return(status: 500, body: "Internal Server Error")

    get settings_access_token_groups_path(access_token), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Error loading groups"
    assert_includes response.body, "Failed to load groups:"
  end

  test "index should handle network errors" do
    sign_in_as(user)

    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .to_raise(Faraday::TimeoutError.new("Connection timeout"))

    get settings_access_token_groups_path(access_token), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Error loading groups"
    assert_includes response.body, "Failed to load groups:"
  end

  test "should redirect to login when not authenticated" do
    get settings_access_token_groups_path(access_token)
    assert_redirected_to new_session_url
  end

  test "should only allow access to user's own access tokens" do
    sign_in_as(user)

    other_user = create(:user)
    other_access_token = create(:access_token, user: other_user)

    get settings_access_token_groups_path(other_access_token)
    assert_response :not_found
  end

  test "managed_groups should be called and cached" do
    sign_in_as(user)

    with_caching do
      response_body = [
        {
          "id" => "group1",
          "username" => "group1",
          "screenName" => "Group 1",
          "isPrivate" => "0",
          "isRestricted" => "0"
        }
      ].to_json

      # Should only be called once due to caching
      request_stub = stub_request(:get, "#{access_token.host}/v4/managedGroups")
        .with(
          headers: {
            "Authorization" => "Bearer #{access_token.token_value}",
            "Accept" => "application/json"
          }
        )
        .to_return(status: 200, body: response_body)

      # First request - should call API
      get settings_access_token_groups_path(access_token), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success

      # Second request - should use cache
      get settings_access_token_groups_path(access_token), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success

      # Should only be called once due to caching
      assert_requested request_stub, times: 1
    end
  end

  test "refresh parameter should bypass cache" do
    sign_in_as(user)

    with_caching do
      response_body = [
        {
          "id" => "group1",
          "username" => "group1",
          "screenName" => "Group 1",
          "isPrivate" => "0",
          "isRestricted" => "0"
        }
      ].to_json

      request_stub = stub_request(:get, "#{access_token.host}/v4/managedGroups")
        .with(
          headers: {
            "Authorization" => "Bearer #{access_token.token_value}",
            "Accept" => "application/json"
          }
        )
        .to_return(status: 200, body: response_body)

      # First request - should call API
      get settings_access_token_groups_path(access_token), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success

      # Second request with refresh - should bypass cache and call API again
      get settings_access_token_groups_path(access_token, refresh: "true"), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success

      # Should be called twice - once initially, once for refresh
      assert_requested request_stub, times: 2
    end
  end

  test "should render turbo stream response with correct content type" do
    sign_in_as(user)

    response_body = [].to_json

    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .to_return(status: 200, body: response_body)

    get settings_access_token_groups_path(access_token), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
    assert_includes response.body, "turbo-stream"
    assert_includes response.body, "groups-select"
  end

  test "should sort groups alphabetically by screen name" do
    sign_in_as(user)

    response_body = [
      {
        "id" => "group3",
        "username" => "zebra_group",
        "screenName" => "Zebra Group",
        "isPrivate" => "0",
        "isRestricted" => "0"
      },
      {
        "id" => "group1",
        "username" => "alpha_group",
        "screenName" => "Alpha Group",
        "isPrivate" => "0",
        "isRestricted" => "0"
      },
      {
        "id" => "group2",
        "username" => "middle_group",
        "screenName" => "Middle Group",
        "isPrivate" => "0",
        "isRestricted" => "0"
      }
    ].to_json

    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .to_return(status: 200, body: response_body)

    get settings_access_token_groups_path(access_token), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    # Extract option values in order
    options = response.body.scan(/<option value="([^"]+)"[^>]*>([^<]+)<\/option>/)
                          .reject { |value, _| value.empty? } # Skip the prompt option

    # Check that groups are sorted alphabetically
    assert_equal ["alpha_group", "middle_group", "zebra_group"], options.map(&:first)
    assert_includes options[0][1], "Alpha Group"
    assert_includes options[1][1], "Middle Group"
    assert_includes options[2][1], "Zebra Group"
  end

  test "should sort groups by username when screen name is missing" do
    sign_in_as(user)

    response_body = [
      {
        "id" => "group2",
        "username" => "zoo",
        "screenName" => "",
        "isPrivate" => "0",
        "isRestricted" => "0"
      },
      {
        "id" => "group1",
        "username" => "apple",
        "screenName" => "",
        "isPrivate" => "0",
        "isRestricted" => "0"
      }
    ].to_json

    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .to_return(status: 200, body: response_body)

    get settings_access_token_groups_path(access_token), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    # Extract option values in order
    options = response.body.scan(/<option value="([^"]+)"[^>]*>([^<]+)<\/option>/)
                          .reject { |value, _| value.empty? }

    # Check that groups are sorted alphabetically by username
    assert_equal ["apple", "zoo"], options.map(&:first)
  end

  test "should include refresh link in help text" do
    sign_in_as(user)

    response_body = [].to_json

    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .to_return(status: 200, body: response_body)

    get settings_access_token_groups_path(access_token), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Refresh"
    assert_includes response.body, "click->groups#refreshGroups"
  end
end
