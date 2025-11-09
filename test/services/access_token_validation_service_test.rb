require "test_helper"

class AccessTokenValidationServiceTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user, status: :validating)
  end

  def mock_client
    @mock_client ||= Minitest::Mock.new
  end

  test "#call should activate token on successful validation" do
    user_info = { username: "testuser", screen_name: "Test User" }
    managed_groups = [{ username: "group1" }, { username: "group2" }]

    mock_client.expect(:whoami, user_info)
    mock_client.expect(:managed_groups, managed_groups)

    service = AccessTokenValidationService.new(access_token)
    service.stub(:freefeed_client, mock_client) do
      service.call
    end

    assert_equal "active", access_token.reload.status
    assert_equal "testuser", access_token.owner
    assert_not_nil access_token.last_used_at
    mock_client.verify
  end

  test "#call should create access_token_detail if it doesn't exist" do
    user_info = { username: "testuser", screen_name: "Test User" }
    managed_groups = [{ username: "group1" }]

    mock_client.expect(:whoami, user_info)
    mock_client.expect(:managed_groups, managed_groups)

    service = AccessTokenValidationService.new(access_token)
    assert_nil access_token.access_token_detail

    service.stub(:freefeed_client, mock_client) do
      service.call
    end

    detail = access_token.reload.access_token_detail
    assert_not_nil detail
    assert_equal "testuser", detail.data["user_info"]["username"]
    assert_equal 1, detail.data["managed_groups"].length
    mock_client.verify
  end

  test "#call should update access_token_detail if it exists" do
    existing_detail = create(:access_token_detail, access_token: access_token)

    user_info = { username: "newuser", screen_name: "New User" }
    managed_groups = []

    mock_client.expect(:whoami, user_info)
    mock_client.expect(:managed_groups, managed_groups)

    service = AccessTokenValidationService.new(access_token)
    service.stub(:freefeed_client, mock_client) do
      service.call
    end

    detail = access_token.reload.access_token_detail
    assert_equal existing_detail.id, detail.id
    assert_equal "newuser", detail.data["user_info"]["username"]
    mock_client.verify
  end

  test "#call should deactivate token on validation failure" do
    mock_client.expect(:whoami, -> { raise StandardError, "API error" })

    service = AccessTokenValidationService.new(access_token)
    service.stub(:freefeed_client, mock_client) do
      service.call
    end

    assert_equal "inactive", access_token.reload.status
  end

  test "#call should disable enabled feeds on validation failure" do
    feed1 = create(:feed, user: user, access_token: access_token, state: :enabled)
    feed2 = create(:feed, user: user, access_token: access_token, state: :enabled)
    feed3 = create(:feed, user: user, access_token: access_token, state: :disabled)

    mock_client.expect(:whoami, -> { raise StandardError, "API error" })

    service = AccessTokenValidationService.new(access_token)
    service.stub(:freefeed_client, mock_client) do
      service.call
    end

    assert_equal "disabled", feed1.reload.state
    assert_equal "disabled", feed2.reload.state
    assert_equal "disabled", feed3.reload.state
  end

  test "#call should deactivate token when managed_groups fails" do
    user_info = { username: "testuser", screen_name: "Test User" }

    mock_client.expect(:whoami, user_info)
    mock_client.expect(:managed_groups, -> { raise StandardError, "Network error" })

    service = AccessTokenValidationService.new(access_token)
    service.stub(:freefeed_client, mock_client) do
      service.call
    end

    # Token should be inactive when managed_groups fails during cache_token_details
    assert_equal "inactive", access_token.reload.status
    mock_client.verify
  end
end
