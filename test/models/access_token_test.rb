require "test_helper"

class AccessTokenTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def access_token
    @access_token ||= create(:access_token)
  end

  def user
    @user ||= create(:user)
  end

  test ".build_with_token stores encrypted token and sets pending status" do
    token = AccessToken.build_with_token(
      name: "Test Token",
      user: user,
      token: "freefeed_token_123"
    )

    assert token.encrypted_token
    assert_equal "freefeed_token_123", token.token
    assert token.pending?

    token.save!

    assert token.reload.encrypted_token
    assert token.reload.pending?
  end

  test "validates presence of name" do
    token = build(:access_token, name: nil)

    assert_not token.valid?
    assert token.errors.of_kind?(:name, :blank)
  end

  test "validates presence of token on create" do
    token = build(:access_token, :without_token)

    assert_not token.valid?
    assert token.errors.of_kind?(:token, :blank)
  end

  test "validates uniqueness of name per user" do
    create(:access_token, name: "Token", user: user)
    duplicate_token = build(:access_token, name: "Token", user: user)

    assert_not duplicate_token.valid?
    assert duplicate_token.errors.of_kind?(:name, :taken)
  end

  test "allows duplicate names across different users" do
    user1 = create(:user)
    user2 = create(:user)
    create(:access_token, name: "Same Name", user: user1)

    duplicate_for_different_user = build(
      :access_token,
      name: "Same Name",
      user: user2
    )

    assert duplicate_for_different_user.valid?
  end

  test "#touch_last_used! updates last_used_at" do
    assert_nil access_token.last_used_at
    access_token.touch_last_used!
    assert_not_nil access_token.reload.last_used_at
  end

  test "active scope returns only active tokens" do
    active_token = create(:access_token, :active)
    inactive_token = create(:access_token, :inactive)
    pending_token = create(:access_token)
    active_tokens = AccessToken.active

    assert_includes active_tokens, active_token
    assert_not_includes active_tokens, inactive_token
    assert_not_includes active_tokens, pending_token
  end

  test "sets default status to pending" do
    assert AccessToken.new.pending?
  end

  test "stores user-provided FreeFeed token" do
    token_value = "TOKEN"

    token = create(
      :access_token,
      token: token_value,
      encrypted_token: token_value
    )

    assert_equal token_value, token.token
  end

  test "can update status to active with owner" do
    token = create(:access_token)
    assert token.pending?
    token.update!(status: :active, owner: "testuser")

    assert token.reload.active?
    assert_equal "testuser", token.owner
  end

  test "can update status to inactive using enum method" do
    token = create(:access_token, :active)
    assert token.active?
    token.inactive!

    assert token.reload.inactive?
  end

  test "#validate_token_async updates status and enqueues job when valid" do
    token = create(:access_token)
    assert token.pending?

    assert_enqueued_with(job: TokenValidationJob, args: [token]) do
      token.validate_token_async
    end

    assert token.reload.validating?
  end

  # Host validation tests
  test "validates presence of host" do
    token = build(:access_token, host: nil)

    assert_not token.valid?
    assert token.errors.of_kind?(:host, :blank)
  end

  test "validates host format requires HTTP(S) URL" do
    ["https://example.com", "http://example.com"].each do |valid_host|
      token = build(:access_token, host: valid_host)
      assert token.valid?, "#{valid_host} should be valid"
    end

    ["ftp://example.com", "example.com", "invalid"].each do |invalid_host|
      token = build(:access_token, host: invalid_host)
      assert_not token.valid?, "#{invalid_host} should be invalid"
      assert token.errors.of_kind?(:host, :invalid)
    end
  end

  test "build_with_token sets default production host" do
    token = AccessToken.build_with_token(
      name: "Test Token",
      user: user,
      token: "freefeed_token_123"
    )

    assert_equal "https://freefeed.net", token.host
  end

  test "build_with_token allows custom host override" do
    custom_host = "https://custom.freefeed.com"
    token = AccessToken.build_with_token(
      name: "Test Token",
      user: user,
      token: "freefeed_token_123",
      host: custom_host
    )

    assert_equal custom_host, token.host
  end

  test "FREEFEED_HOSTS contains expected standard hosts" do
    assert_equal "https://freefeed.net", AccessToken::FREEFEED_HOSTS[:production][:url]
    assert_equal "https://candy.freefeed.net", AccessToken::FREEFEED_HOSTS[:staging][:url]
    assert_equal "https://beta.freefeed.net", AccessToken::FREEFEED_HOSTS[:beta][:url]
  end

  test "destroying access token disables and nullifies associated feeds in single query" do
    token = create(:access_token, :active)
    enabled_feed = create(:feed, access_token: token, state: :enabled)
    disabled_feed = create(:feed, access_token: token, state: :disabled)
    another_disabled_feed = create(:feed, access_token: token, state: :disabled)

    # Track database queries to ensure single query
    queries = []
    ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      queries << event.payload[:sql] if event.payload[:sql].include?("UPDATE")
    end

    token.destroy!

    # Should have exactly one UPDATE query for feeds
    feed_update_queries = queries.select { |q| q.include?("feeds") && q.include?("UPDATE") }
    assert_equal 1, feed_update_queries.size, "Expected exactly 1 UPDATE query for feeds, got #{feed_update_queries.size}"

    # All feeds should be disabled and have null access_token_id
    [enabled_feed, disabled_feed, another_disabled_feed].each do |feed|
      feed.reload
      assert_equal "disabled", feed.state
      assert_nil feed.access_token_id
    end
  ensure
    ActiveSupport::Notifications.unsubscribe("sql.active_record")
  end

  test "should disable enabled feeds when token validation service marks token inactive" do
    access_token = create(:access_token, status: :validating)
    enabled_feed = create(:feed, access_token: access_token, state: :enabled)
    another_disabled_feed = create(:feed, access_token: access_token, state: :disabled)
    disabled_feed = create(:feed, access_token: access_token, state: :disabled)

    # Stub HTTP request to return 401 Unauthorized, triggering the rescue block
    stub_request(:get, "#{access_token.host}/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => "Bearer #{access_token.token_value}",
          "Accept" => "application/json"
        }
      )
      .to_return(status: 401, body: "")

    service = AccessTokenValidationService.new(access_token)
    service.call

    access_token.reload
    enabled_feed.reload
    another_disabled_feed.reload
    disabled_feed.reload

    assert_equal "inactive", access_token.status
    assert_equal "disabled", enabled_feed.state
    assert_equal "disabled", another_disabled_feed.state
    assert_equal "disabled", disabled_feed.state

    # Token reference should remain (unlike destroy callback)
    assert_equal access_token, enabled_feed.access_token
    assert_equal access_token, another_disabled_feed.access_token
    assert_equal access_token, disabled_feed.access_token
  end
end
