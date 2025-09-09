require "test_helper"

class AccessTokenTest < ActiveSupport::TestCase
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
end
