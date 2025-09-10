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
    assert_includes token.errors[:name], "can't be blank"
  end

  test "validates presence of token on create" do
    token = build(:access_token, :without_token)

    assert_not token.valid?
    assert_includes token.errors[:token], "can't be blank"
  end

  test "validates uniqueness of name per user" do
    create(:access_token, name: "Token", user: user)
    duplicate_token = build(:access_token, name: "Token", user: user)

    assert_not duplicate_token.valid?
    assert_includes duplicate_token.errors[:name], "has already been taken"
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

  test "stores user-provided Freefeed token" do
    token_value = "TOKEN"

    token = create(
      :access_token,
      token: token_value,
      encrypted_token: token_value
    )

    assert_equal token_value, token.token
  end

  test "validates user tokens limit" do
    user = create(:user)
    AccessToken::MAX_TOKENS_PER_USER.times { create(:access_token, user: user) }
    new_token = build(:access_token, user: user)

    assert_not new_token.valid?
    assert_includes new_token.errors[:user], "cannot have more than #{AccessToken::MAX_TOKENS_PER_USER} access tokens"
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

  test "#validate_token_async does nothing when token is invalid" do
    token = build(:access_token, name: nil) # Invalid token
    assert_not token.valid?

    assert_no_enqueued_jobs do
      token.validate_token_async
    end

    assert token.pending?
  end

  # Host validation tests
  test "validates presence of host" do
    token = build(:access_token, host: nil)

    assert_not token.valid?
    assert_includes token.errors[:host], "can't be blank"
  end

  test "validates host format requires HTTP(S) URL" do
    ["https://example.com", "http://example.com"].each do |valid_host|
      token = build(:access_token, host: valid_host)
      assert token.valid?, "#{valid_host} should be valid"
    end

    ["ftp://example.com", "example.com", "invalid"].each do |invalid_host|
      token = build(:access_token, host: invalid_host)
      assert_not token.valid?, "#{invalid_host} should be invalid"
      assert_includes token.errors[:host], "must be a valid HTTP(S) URL"
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
    assert_equal "https://freefeed.net", AccessToken::FREEFEED_HOSTS["production"]
    assert_equal "https://candy.freefeed.net", AccessToken::FREEFEED_HOSTS["staging"]
    assert_equal "https://beta.freefeed.net", AccessToken::FREEFEED_HOSTS["beta"]
  end
end
