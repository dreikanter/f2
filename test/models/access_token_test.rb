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

  test "auto-generates name when blank" do
    token = build(:access_token, name: nil)
    assert token.valid?
    assert_equal "Token 1", token.name
  end

  test "auto-generates unique sequential names for same user" do
    user = create(:user)
    token1 = create(:access_token, name: nil, user: user)
    token2 = create(:access_token, name: nil, user: user)
    token3 = create(:access_token, name: nil, user: user)

    assert_equal "Token 1", token1.name
    assert_equal "Token 2", token2.name
    assert_equal "Token 3", token3.name
  end

  test "auto-generates name that skips existing names" do
    user = create(:user)
    create(:access_token, name: "Token 1", user: user)
    create(:access_token, name: "Token 2", user: user)

    token = create(:access_token, name: nil, user: user)
    assert_equal "Token 3", token.name
  end

  test "auto-generates name fills gaps in sequence" do
    user = create(:user)
    create(:access_token, name: "Token 2", user: user)

    token = create(:access_token, name: nil, user: user)
    assert_equal "Token 1", token.name
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

  test "build_with_token allows host override" do
    staging_host = AccessToken::FREEFEED_HOSTS[:staging][:url]
    token = AccessToken.build_with_token(
      name: "Test Token",
      user: user,
      token: "freefeed_token_123",
      host: staging_host
    )

    assert_equal staging_host, token.host
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

  test "#host_domain should return domain from FREEFEED_HOSTS for known hosts" do
    token = build(:access_token, host: "https://freefeed.net")
    assert_equal "freefeed.net", token.host_domain

    token = build(:access_token, host: "https://candy.freefeed.net")
    assert_equal "candy.freefeed.net", token.host_domain

    token = build(:access_token, host: "https://beta.freefeed.net")
    assert_equal "beta.freefeed.net", token.host_domain
  end

  test "#host_domain should raise error for unknown hosts" do
    token = build(:access_token, host: "https://custom.example.com")
    assert_raises(NoMethodError) { token.host_domain }
  end

  test "#username_with_host should return username with domain" do
    token = build(:access_token, host: "https://freefeed.net", owner: "testuser")
    assert_equal "testuser@freefeed.net", token.username_with_host
  end

  test "#username_with_host should return nil when owner is not set" do
    token = build(:access_token, host: "https://freefeed.net", owner: nil)
    assert_nil token.username_with_host
  end

  test "FREEFEED_HOSTS URLs should all be valid HTTP(S) URLs" do
    AccessToken::FREEFEED_HOSTS.each do |key, config|
      token = build(:access_token, host: config[:url])
      assert token.valid?, "#{key} host URL (#{config[:url]}) should be valid"
    end
  end

  test "FREEFEED_HOSTS should have complete configuration for all hosts" do
    required_fields = [:url, :display_name, :domain, :token_url]

    AccessToken::FREEFEED_HOSTS.each do |key, config|
      required_fields.each do |field|
        assert config.key?(field), "#{key} is missing required field: #{field}"
        assert config[field].present?, "#{key} has blank value for field: #{field}"
      end

      # Verify domain is a valid hostname (no protocol, no path)
      assert_no_match %r{https?://}, config[:domain], "#{key} domain should not include protocol"
      assert_no_match %r{/}, config[:domain], "#{key} domain should not include path"
    end
  end

  test "#disable_associated_feeds should disable only enabled feeds and clear access_token_id" do
    token = create(:access_token, :active)
    enabled_feed1 = create(:feed, access_token: token, state: :enabled)
    enabled_feed2 = create(:feed, access_token: token, state: :enabled)
    disabled_feed = create(:feed, access_token: token, state: :disabled)

    token.disable_associated_feeds

    assert_equal "disabled", enabled_feed1.reload.state
    assert_nil enabled_feed1.access_token_id
    assert_equal "disabled", enabled_feed2.reload.state
    assert_nil enabled_feed2.access_token_id

    # Already disabled feed should remain unchanged
    assert_equal "disabled", disabled_feed.reload.state
    assert_equal token.id, disabled_feed.access_token_id
  end
end
