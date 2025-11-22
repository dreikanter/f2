require "test_helper"

class GroupsControllerTest < ActionDispatch::IntegrationTest
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

  test "should require authentication" do
    get settings_access_token_groups_path(active_token)
    assert_redirected_to new_session_path
  end

  test "should return Turbo Stream with fetched groups" do
    sign_in_as user

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
      .with(headers: { "Authorization" => "Bearer #{active_token.encrypted_token}", "Accept" => "application/json" })
      .to_return(status: 200, body: groups_response.to_json)

    get settings_access_token_groups_path(active_token), params: { feed_id: feed.id }

    assert_response :success
    assert_includes ["text/vnd.turbo-stream.html", "text/vnd.turbo-stream.html; charset=utf-8"], response.media_type
    assert_match(/select.*feed\[target_group\]/, response.body)
    assert_match(/testgroup1/, response.body)
    assert_match(/testgroup2/, response.body)
  end

  test "sorts groups alphabetically" do
    sign_in_as user

    groups_response = [
      {
        "id" => "group1",
        "username" => "zebra",
        "screenName" => "Zebra",
        "isPrivate" => "0",
        "isRestricted" => "0"
      },
      {
        "id" => "group2",
        "username" => "alpha",
        "screenName" => "Alpha",
        "isPrivate" => "0",
        "isRestricted" => "0"
      },
      {
        "id" => "group3",
        "username" => "beta",
        "screenName" => "Beta",
        "isPrivate" => "0",
        "isRestricted" => "0"
      }
    ]

    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .to_return(status: 200, body: groups_response.to_json)

    get settings_access_token_groups_path(active_token)

    assert_response :success
    assert_match(/alpha.*beta.*zebra/m, response.body)
  end

  test "should render disabled selector for non-existent token" do
    sign_in_as user

    get settings_access_token_groups_path(access_token_id: -1)

    assert_response :success
    assert_match(/Unable to load groups/, response.body)
  end

  test "should render disabled selector for other user's token" do
    sign_in_as user

    get settings_access_token_groups_path(other_users_token)

    assert_response :success
    assert_match(/Unable to load groups/, response.body)
  end

  test "should render disabled selector for inactive token" do
    sign_in_as user

    get settings_access_token_groups_path(inactive_token)

    assert_response :success
    assert_match(/This token is inactive/, response.body)
  end

  test "handles API errors gracefully" do
    sign_in_as user

    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .to_return(status: 500, body: "Internal Server Error")

    get settings_access_token_groups_path(active_token)

    assert_response :success
    assert_match(/Could not load groups/, response.body)
    assert_match(/Retry/, response.body)
  end

  test "handles unauthorized token without retry link" do
    sign_in_as user

    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .to_return(status: 401, body: "Unauthorized")

    get settings_access_token_groups_path(active_token)

    assert_response :success
    assert_match(/Unable to load groups/, response.body)
    assert_no_match(/Retry/, response.body)
  end

  test "handles empty groups list with appropriate message" do
    sign_in_as user

    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .to_return(status: 200, body: [].to_json)

    get settings_access_token_groups_path(active_token)

    assert_response :success
    assert_match(/doesn't manage any groups yet/, response.body)
    assert_match(/Retry/, response.body)
  end

  test "should purge cache when retry parameter is present" do
    sign_in_as user

    # Stubbing sequential requests
    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .to_return(
        { status: 200, body: [].to_json },
        { status: 200, body: [{ "username" => "newgroup" }].to_json }
      )

    get settings_access_token_groups_path(active_token)
    assert_match(/doesn't manage any groups yet/, response.body)

    get settings_access_token_groups_path(active_token, retry: 1)
    assert_match(/newgroup/, response.body)
  end

  test "should render disabled select for error states" do
    sign_in_as user

    stub_request(:get, "#{active_token.host}/v4/managedGroups")
      .to_return(status: 500, body: "Internal Server Error")

    get settings_access_token_groups_path(active_token)

    assert_response :success
    assert_match(/select.*disabled/, response.body)
    assert_match(/Could not load groups/, response.body)
    assert_no_match(/input.*type="text"/, response.body)
  end
end
