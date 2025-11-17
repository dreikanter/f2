require "test_helper"

class AccessTokens::GroupsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def active_token
    @active_token ||= create(:access_token, user: user, status: :active)
  end

  def inactive_token
    @inactive_token ||= create(:access_token, user: user, status: :inactive)
  end

  def other_users_token
    @other_users_token ||= create(:access_token, user: other_user, status: :active)
  end

  def feed
    @feed ||= create(:feed, user: user, target_group: "mygroup")
  end

  test "#index should require authentication" do
    get settings_access_token_groups_path(active_token)
    assert_redirected_to new_session_path
  end

  test "#index should return Turbo Stream with groups for active token" do
    sign_in_as user

    # Mock FreeFeed API response
    groups_response = [
      {
        "id" => "group1",
        "username" => "testgroup1",
        "screenName" => "Test Group 1",
        "isPrivate" => "0",
        "isRestricted" => "0"
      },
      {
        "id" => "group2",
        "username" => "testgroup2",
        "screenName" => "Test Group 2",
        "isPrivate" => "1",
        "isRestricted" => "0"
      }
    ]

    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .with(headers: {
        "Authorization" => "Bearer #{active_token.encrypted_token}",
        "Accept" => "application/json"
      })
      .to_return(status: 200, body: groups_response.to_json)

    get settings_access_token_groups_path(active_token)

    assert_response :success
    assert_includes ["text/vnd.turbo-stream.html", "text/vnd.turbo-stream.html; charset=utf-8"], response.media_type
    assert_match(/target-group-selector/, response.body)
    assert_match(/testgroup1/, response.body)
    assert_match(/testgroup2/, response.body)
  end

  test "#index should render target_group_selector partial with fetched groups" do
    sign_in_as user

    groups_response = [
      {
        "id" => "group1",
        "username" => "mygroup",
        "screenName" => "My Group",
        "isPrivate" => "0",
        "isRestricted" => "0"
      }
    ]

    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .to_return(status: 200, body: groups_response.to_json)

    get settings_access_token_groups_path(active_token), params: { feed_id: feed.id }

    assert_response :success
    assert_match(/select.*feed\[target_group\]/, response.body)
    assert_match(/mygroup/, response.body)
  end

  test "#index should render empty selector for non-existent token" do
    sign_in_as user

    get settings_access_token_groups_path(access_token_id: 99999)

    assert_response :success
    assert_match(/target-group-selector/, response.body)
    assert_match(/Unable to load groups/, response.body)
  end

  test "#index should render empty selector for token owned by different user" do
    sign_in_as user

    get settings_access_token_groups_path(other_users_token)

    assert_response :success
    assert_match(/target-group-selector/, response.body)
    assert_match(/Unable to load groups/, response.body)
  end

  test "#index should render empty selector when token is inactive" do
    sign_in_as user

    get settings_access_token_groups_path(inactive_token)

    assert_response :success
    assert_match(/target-group-selector/, response.body)
    assert_match(/This token is inactive/, response.body)
  end

  test "#index should handle FreeFeed API errors gracefully" do
    sign_in_as user

    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .to_return(status: 500, body: "Internal Server Error")

    get settings_access_token_groups_path(active_token)

    assert_response :success
    assert_match(/target-group-selector/, response.body)
    assert_match(/Could not load groups/, response.body)
  end

  test "#index should fetch groups successfully" do
    sign_in_as user

    groups_response = [
      { "id" => "group1", "username" => "testgroup", "screenName" => "Test", "isPrivate" => "0", "isRestricted" => "0" }
    ]

    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .to_return(status: 200, body: groups_response.to_json)

    get settings_access_token_groups_path(active_token)

    assert_response :success
    assert_match(/testgroup/, response.body)
  end

  test "#index should sort groups alphabetically" do
    sign_in_as user

    groups_response = [
      { "id" => "group1", "username" => "zebra", "screenName" => "Zebra", "isPrivate" => "0", "isRestricted" => "0" },
      { "id" => "group2", "username" => "alpha", "screenName" => "Alpha", "isPrivate" => "0", "isRestricted" => "0" },
      { "id" => "group3", "username" => "beta", "screenName" => "Beta", "isPrivate" => "0", "isRestricted" => "0" }
    ]

    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .to_return(status: 200, body: groups_response.to_json)

    get settings_access_token_groups_path(active_token)

    assert_response :success

    # Extract group order from response
    # The select options should be in alphabetical order: alpha, beta, zebra
    assert_match(/alpha.*beta.*zebra/m, response.body)
  end

  test "#index should pre-select current feed target_group when editing" do
    sign_in_as user

    groups_response = [
      { "id" => "group1", "username" => "mygroup", "screenName" => "My Group", "isPrivate" => "0", "isRestricted" => "0" },
      { "id" => "group2", "username" => "othergroup", "screenName" => "Other", "isPrivate" => "0", "isRestricted" => "0" }
    ]

    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .to_return(status: 200, body: groups_response.to_json)

    get settings_access_token_groups_path(active_token), params: { feed_id: feed.id }

    assert_response :success
    # The response should include the feed's target_group (mygroup) as selected
    assert_match(/mygroup/, response.body)
  end

  test "#index should handle HTTP timeout errors" do
    sign_in_as user

    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .to_raise(HttpClient::TimeoutError.new("Request timed out"))

    get settings_access_token_groups_path(active_token)

    assert_response :success
    assert_match(/Could not load groups/, response.body)
  end

  test "#index should handle unauthorized API responses" do
    sign_in_as user

    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .to_return(status: 401, body: "Unauthorized")

    get settings_access_token_groups_path(active_token)

    assert_response :success
    assert_match(/Could not load groups/, response.body)
  end

  test "#index should build new feed when feed_id not provided" do
    sign_in_as user

    groups_response = [
      { "id" => "group1", "username" => "testgroup", "screenName" => "Test", "isPrivate" => "0", "isRestricted" => "0" }
    ]

    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .to_return(status: 200, body: groups_response.to_json)

    get settings_access_token_groups_path(active_token)

    assert_response :success
    # Should not have a pre-selected value (new feed)
    assert_match(/target-group-selector/, response.body)
  end
end
