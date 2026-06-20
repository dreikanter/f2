require "test_helper"

class AccessTokenValidationServiceTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user, status: :validating)
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

    service = AccessTokenValidationService.new(access_token)
    service.call

    assert_equal "active", access_token.reload.status
    assert_equal "testuser", access_token.owner
    assert_equal "user123", access_token.freefeed_user_id
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
      .to_return(
        status: 200,
        body: [
          { id: "group1", username: "group1", screenName: "Group 1" }
        ].to_json
      )

    service = AccessTokenValidationService.new(access_token)
    assert_nil access_token.access_token_detail

    service.call

    detail = access_token.reload.access_token_detail
    assert_not_nil detail
    assert_equal "testuser", detail.data["user_info"]["username"]
    assert_equal 1, detail.data["managed_groups"].length
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

    service = AccessTokenValidationService.new(access_token)
    service.call

    detail = access_token.reload.access_token_detail
    assert_equal existing_detail.id, detail.id
    assert_equal "newuser", detail.data["user_info"]["username"]
  end

  test "#call should deactivate token on invalid token error" do
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
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .to_return(status: 403, body: { err: "invalid JWT payload format" }.to_json)

    service = AccessTokenValidationService.new(access_token)
    service.call

    assert_equal "inactive", access_token.reload.status
  end

  test "#call should not disable token on transient errors" do
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
    feed1 = create(:feed, user: user, access_token: access_token, state: :enabled)
    feed2 = create(:feed, user: user, access_token: access_token, state: :enabled)
    feed3 = create(:feed, user: user, access_token: access_token, state: :disabled)

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
