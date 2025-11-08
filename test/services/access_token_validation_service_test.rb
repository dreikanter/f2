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

  test "#call should set name if it's blank" do
    access_token.update!(name: nil)
    user_info = { username: "testuser", screen_name: "Test User" }
    managed_groups = []

    mock_client.expect(:whoami, user_info)
    mock_client.expect(:managed_groups, managed_groups)

    service = AccessTokenValidationService.new(access_token)
    service.stub(:freefeed_client, mock_client) do
      service.call
    end

    assert_equal "testuser@#{access_token.host_domain}", access_token.reload.name
    mock_client.verify
  end

  test "#call should not update name if it's a custom name" do
    custom_name = "My Custom Token Name"
    access_token.update!(name: custom_name)
    user_info = { username: "testuser", screen_name: "Test User" }
    managed_groups = []

    mock_client.expect(:whoami, user_info)
    mock_client.expect(:managed_groups, managed_groups)

    service = AccessTokenValidationService.new(access_token)
    service.stub(:freefeed_client, mock_client) do
      service.call
    end

    assert_equal custom_name, access_token.reload.name
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
    assert_not_nil detail.expires_at
    mock_client.verify
  end

  test "#call should update access_token_detail if it exists" do
    existing_detail = create(:access_token_detail, access_token: access_token)
    old_expires_at = existing_detail.expires_at

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
    assert detail.expires_at > old_expires_at
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

  test "#call should deactivate token when auto-generated name conflicts" do
    access_token.update!(name: nil)

    # Create another token with the name that would be auto-generated
    user_info = { username: "testuser", screen_name: "Test User" }
    conflicting_name = "#{user_info[:username]}@#{access_token.host_domain}"
    create(:access_token, user: user, name: conflicting_name)

    mock_client.expect(:whoami, user_info)
    mock_client.expect(:managed_groups, [])

    service = AccessTokenValidationService.new(access_token)
    service.stub(:freefeed_client, mock_client) do
      service.call
    end

    # Token should be deactivated, not stuck in validating state
    assert_equal "inactive", access_token.reload.status
  end

  test "#call should handle concurrent detail creation" do
    user_info = { username: "testuser", screen_name: "Test User" }
    managed_groups = []

    mock_client.expect(:whoami, user_info)
    mock_client.expect(:managed_groups, managed_groups)

    service = AccessTokenValidationService.new(access_token)
    original_cache_method = service.method(:cache_token_details)

    # Simulate concurrent creation by stubbing cache_token_details
    service.define_singleton_method(:cache_token_details) do |user_info, managed_groups|
      # Create the detail with different data to simulate concurrent job
      AccessTokenDetail.create!(
        access_token: access_token,
        data: { user_info: { username: "concurrent" }, managed_groups: [] },
        expires_at: AccessTokenDetail::TTL.from_now
      )
      # This will trigger RecordNotUnique in the rescue path
      original_cache_method.call(user_info, managed_groups)
    end

    service.stub(:freefeed_client, mock_client) do
      service.call
    end

    # Token should still be active despite the race condition
    assert_equal "active", access_token.reload.status
    detail = access_token.access_token_detail
    assert_not_nil detail
    # Verify the detail was updated with correct data (not the concurrent job's data)
    assert_equal "testuser", detail.data["user_info"]["username"]
    mock_client.verify
  end

  test "#call should keep token active when managed_groups fails" do
    user_info = { username: "testuser", screen_name: "Test User" }

    mock_client.expect(:whoami, user_info)
    mock_client.expect(:managed_groups, -> { raise StandardError, "Network error" })

    service = AccessTokenValidationService.new(access_token)
    service.stub(:freefeed_client, mock_client) do
      service.call
    end

    # Token should still be active despite managed_groups failure
    assert_equal "active", access_token.reload.status
    assert_equal "testuser", access_token.owner
    # Detail should be cached even when managed_groups fails
    detail = access_token.access_token_detail
    assert_not_nil detail
    assert_equal "testuser", detail.data["user_info"]["username"]
    # Managed groups key exists (value doesn't matter for this test)
    assert detail.data.key?("managed_groups")
    mock_client.verify
  end

  test "#call should keep token active when cache_token_details fails" do
    user_info = { username: "testuser", screen_name: "Test User" }

    mock_client.expect(:whoami, user_info)
    mock_client.expect(:managed_groups, [])

    service = AccessTokenValidationService.new(access_token)

    # Stub cache_token_details to raise an error
    service.define_singleton_method(:cache_token_details) do |user_info, managed_groups|
      raise ActiveRecord::RecordInvalid, "Validation failed"
    end

    service.stub(:freefeed_client, mock_client) do
      service.call
    end

    # Token should still be active despite caching failure
    assert_equal "active", access_token.reload.status
    assert_equal "testuser", access_token.owner
    # Detail should not exist since caching failed
    assert_nil access_token.access_token_detail
    mock_client.verify
  end
end
