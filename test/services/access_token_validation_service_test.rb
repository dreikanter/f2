require "test_helper"

class AccessTokenValidationServiceTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user, status: :validating)
  end

  def stub_app_token_info(scopes: AccessToken::TOKEN_SCOPES)
    stub_request(:get, "#{access_token.host}/v2/app-tokens/current")
      .to_return(status: 200, body: { token: { id: "token-1", scopes: scopes } }.to_json)
  end

  def stub_successful_account_calls
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .to_return(status: 200, body: { users: { id: "user123", username: "testuser" } }.to_json)
    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .to_return(status: 200, body: [].to_json)
  end

  test "#call should activate token on successful validation" do
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: {
          users: {
            id: "user123",
            username: "testuser",
            screenName: "Test User",
            email: "test@example.com"
          }
        }.to_json
      )

    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: [
          { id: "group1", username: "group1", screenName: "Group 1" },
          { id: "group2", username: "group2", screenName: "Group 2" }
        ].to_json
      )

    stub_app_token_info

    service = AccessTokenValidationService.new(access_token)
    service.call

    assert_equal "active", access_token.reload.status
    assert_equal "testuser", access_token.owner
    assert_equal "user123", access_token.freefeed_user_id
    assert_equal AccessToken::TOKEN_SCOPES, access_token.scopes
    assert_not_nil access_token.last_used_at
  end

  test "#call should create access_token_detail if it doesn't exist" do
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: {
          users: {
            id: "user123",
            username: "testuser",
            screenName: "Test User",
            profilePictureLargeUrl: "https://media.freefeed.net/profilepics/user123_75.jpg"
          }
        }.to_json
      )

    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: [
          { id: "group1", username: "group1", screenName: "Group 1" }
        ].to_json
      )

    stub_app_token_info

    service = AccessTokenValidationService.new(access_token)
    assert_nil access_token.access_token_detail

    service.call

    detail = access_token.reload.access_token_detail
    assert_not_nil detail
    assert_equal "testuser", detail.freefeed_user_info["username"]
    assert_equal "https://media.freefeed.net/profilepics/user123_75.jpg",
      detail.freefeed_user_info["profile_picture_url"]
    assert_equal 1, detail.managed_groups.length
  end

  test "#call should update access_token_detail if it exists" do
    existing_detail = create(:access_token_detail, access_token: access_token)

    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: {
          users: {
            id: "user456",
            username: "newuser",
            screenName: "New User"
          }
        }.to_json
      )

    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: [].to_json
      )

    stub_app_token_info

    service = AccessTokenValidationService.new(access_token)
    service.call

    detail = access_token.reload.access_token_detail
    assert_equal existing_detail.id, detail.id
    assert_equal "newuser", detail.freefeed_user_info["username"]
  end

  test "#call should settle an in-flight groups refresh" do
    detail = create(:access_token_detail, access_token: access_token)
    detail.begin_groups_refresh!

    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .to_return(status: 200, body: { users: { id: "user123", username: "testuser" } }.to_json)
    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .to_return(status: 200, body: [].to_json)
    stub_app_token_info

    AccessTokenValidationService.new(access_token).call

    detail.reload
    assert_nil detail.groups_refresh_state
    assert_not detail.groups_refresh_running?
  end

  test "#call should clear a failed groups refresh" do
    detail = create(:access_token_detail, access_token: access_token)
    detail.fail_groups_refresh!

    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .to_return(status: 200, body: { users: { id: "user123", username: "testuser" } }.to_json)
    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .to_return(status: 200, body: [].to_json)
    stub_app_token_info

    AccessTokenValidationService.new(access_token).call

    assert_not detail.reload.groups_refresh_failed?
  end

  test "#call should persist a partial scope list" do
    stub_successful_account_calls
    stub_app_token_info(scopes: ["read-my-info", "manage-posts"])

    AccessTokenValidationService.new(access_token).call

    assert_equal ["read-my-info", "manage-posts"], access_token.reload.scopes
    assert_not access_token.allows_scope?(AccessToken::READ_USERS_INFO_SCOPE)
  end

  test "#call should leave scopes unknown for a session token" do
    stub_successful_account_calls
    stub_request(:get, "#{access_token.host}/v2/app-tokens/current")
      .to_return(
        status: 400,
        body: { err: "This method is only available with the application token" }.to_json
      )

    AccessTokenValidationService.new(access_token).call

    access_token.reload
    assert access_token.active?
    assert_nil access_token.scopes
    assert access_token.allows_scope?(AccessToken::READ_USERS_INFO_SCOPE)
  end

  test "#call should activate the token when the scopes request fails" do
    stub_successful_account_calls
    stub_request(:get, "#{access_token.host}/v2/app-tokens/current")
      .to_return(status: 500, body: "Internal Server Error")

    AccessTokenValidationService.new(access_token).call

    access_token.reload
    assert access_token.active?
    assert_nil access_token.scopes
  end

  test "#call should skip the account calls when the token lacks read-my-info" do
    stub_app_token_info(scopes: ["manage-posts"])

    AccessTokenValidationService.new(access_token).call

    assert_not_requested :get, "#{access_token.host}/v4/users/whoami"
    assert_not_requested :get, "#{access_token.host}/v4/managedGroups"
  end

  test "#call should record the scopes it disabled an under-permissioned token for" do
    stub_app_token_info(scopes: ["manage-posts"])

    AccessTokenValidationService.new(access_token).call

    access_token.reload
    assert access_token.inactive?
    assert_equal ["manage-posts"], access_token.scopes
    assert_not access_token.allows_scope?(AccessToken::READ_MY_INFO_SCOPE)
  end

  test "#call should report a missing identity permission as its own event" do
    access_token.update!(status: :active)
    feed = create(:feed, user: user, access_token: access_token, state: :enabled)
    access_token.update!(status: :validating)
    stub_app_token_info(scopes: ["manage-posts"])

    AccessTokenValidationService.new(access_token).call

    assert_equal "disabled", feed.reload.state
    event = Event.find_by!(subject: access_token)
    assert_equal "access_token_missing_scope", event.type
    assert_equal [feed.id], event.metadata["disabled_feed_ids"]
  end

  test "#call should still validate a token whose scopes are unknown" do
    stub_successful_account_calls
    stub_request(:get, "#{access_token.host}/v2/app-tokens/current")
      .to_return(
        status: 400,
        body: { err: "This method is only available with the application token" }.to_json
      )

    AccessTokenValidationService.new(access_token).call

    assert access_token.reload.active?
    assert_requested :get, "#{access_token.host}/v4/users/whoami"
  end

  test "#call should disable the token when the scopes request reports it dead" do
    access_token.update!(status: :active)
    feed = create(:feed, user: user, access_token: access_token, state: :enabled)
    access_token.update!(status: :validating)
    stub_successful_account_calls
    stub_request(:get, "#{access_token.host}/v2/app-tokens/current")
      .to_return(status: 401, body: { err: "inactive or expired token" }.to_json)

    AccessTokenValidationService.new(access_token).call

    assert access_token.reload.inactive?
    assert_equal "disabled", feed.reload.state
  end

  test "#call should keep the token active when it just can't read its own scopes" do
    stub_successful_account_calls
    stub_request(:get, "#{access_token.host}/v2/app-tokens/current")
      .to_return(status: 401, body: { err: "token has no access to this API method" }.to_json)

    AccessTokenValidationService.new(access_token).call

    access_token.reload
    assert access_token.active?
    assert_nil access_token.scopes
  end

  test "#call should reopen the gate when a revalidation can't read scopes" do
    access_token.update!(scopes: ["read-my-info"])
    stub_successful_account_calls
    stub_request(:get, "#{access_token.host}/v2/app-tokens/current")
      .to_return(status: 500, body: "Internal Server Error")

    AccessTokenValidationService.new(access_token).call

    assert_nil access_token.reload.scopes
  end

  test "#call should deactivate token on invalid token error" do
    stub_app_token_info
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json"
        }
      )
      .to_return(status: 401, body: { err: "inactive or expired token" }.to_json)

    service = AccessTokenValidationService.new(access_token)
    service.call

    assert_equal "inactive", access_token.reload.status
  end

  test "#call should deactivate token on forbidden error" do
    stub_app_token_info
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .to_return(status: 403, body: { err: "invalid JWT payload format" }.to_json)

    service = AccessTokenValidationService.new(access_token)
    service.call

    assert_equal "inactive", access_token.reload.status
  end

  test "#call should not disable token on transient errors" do
    stub_app_token_info
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json"
        }
      )
      .to_return(status: 500, body: "Internal Server Error")

    service = AccessTokenValidationService.new(access_token)

    assert_raises(FreefeedClient::Error) do
      service.call
    end

    assert_equal "validating", access_token.reload.status
  end

  test "#call should disable enabled feeds on invalid token error" do
    # Feeds can only become enabled while the token is active; re-validation
    # of the live token starts after that.
    access_token.update!(status: :active)
    feed1 = create(:feed, user: user, access_token: access_token, state: :enabled)
    feed2 = create(:feed, user: user, access_token: access_token, state: :enabled)
    feed3 = create(:feed, user: user, access_token: access_token, state: :disabled)
    access_token.update!(status: :validating)

    stub_app_token_info
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json"
        }
      )
      .to_return(status: 401, body: { err: "inactive or expired token" }.to_json)

    service = AccessTokenValidationService.new(access_token)

    assert_difference "Event.count", 1 do
      service.call
    end

    assert_equal "disabled", feed1.reload.state
    assert_equal "disabled", feed2.reload.state
    assert_equal "disabled", feed3.reload.state

    event = Event.find_by!(
      type: "access_token_validation_failed",
      subject: access_token
    )

    assert_equal access_token.user, event.user
    assert_equal "warning", event.level
    assert_equal [feed1.id, feed2.id].sort, event.metadata["disabled_feed_ids"].sort
    assert_equal 2, event.metadata["disabled_count"]
  end

  test "#call should not create event when no enabled feeds exist" do
    create(:feed, user: user, access_token: access_token, state: :disabled)

    stub_app_token_info
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json"
        }
      )
      .to_return(status: 401, body: { err: "inactive or expired token" }.to_json)

    service = AccessTokenValidationService.new(access_token)

    assert_no_difference "Event.count" do
      service.call
    end

    assert_equal "inactive", access_token.reload.status
  end

  test "#call should deactivate token when managed_groups returns invalid token error" do
    stub_app_token_info
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json"
        }
      )
      .to_return(
        status: 200,
        body: {
          users: {
            id: "user123",
            username: "testuser",
            screenName: "Test User"
          }
        }.to_json
      )

    stub_request(:get, "#{access_token.host}/v4/managedGroups")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.encrypted_token}",
          "Accept" => "application/json"
        }
      )
      .to_return(status: 401, body: { err: "inactive or expired token" }.to_json)

    service = AccessTokenValidationService.new(access_token)
    service.call

    assert_equal "inactive", access_token.reload.status
  end
end
