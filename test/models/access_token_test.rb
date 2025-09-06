require "test_helper"

class AccessTokenTest < ActiveSupport::TestCase
  def access_token
    @access_token ||= create(:access_token)
  end

  def user
    @user ||= create(:user)
  end

  test "generates token digest on create" do
    token = AccessToken.new(name: "Test Token", user: user)
    assert_nil token.token_digest
    token.save!
    assert_not_nil token.token_digest
    assert_not_nil token.token
  end

  test "validates presence of name" do
    token = build(:access_token, name: nil)
    assert_not token.valid?
    assert_includes token.errors[:name], "can't be blank"
  end

  test "validates uniqueness of name per user" do
    create(:access_token, name: "My Token", user: user)
    duplicate_token = build(:access_token, name: "My Token", user: user)
    assert_not duplicate_token.valid?
    assert_includes duplicate_token.errors[:name], "has already been taken"
  end

  test "allows duplicate names across different users" do
    user1 = create(:user)
    user2 = create(:user)
    create(:access_token, name: "Same Name", user: user1)
    duplicate_for_different_user = build(:access_token, name: "Same Name", user: user2)
    assert duplicate_for_different_user.valid?
  end

  test "authenticates with correct token" do
    token = create(:access_token)
    token_value = token.token
    assert token.authenticate(token_value)
  end

  test "does not authenticate with incorrect token" do
    assert_not access_token.authenticate("wrong_token")
  end

  test "does not authenticate when inactive" do
    token = create(:access_token, :inactive)
    assert_not token.authenticate("any_token")
  end

  test "deactivate! sets is_active to false" do
    assert access_token.is_active?
    access_token.deactivate!
    assert_not access_token.is_active?
  end

  test "touch_last_used! updates last_used_at" do
    assert_nil access_token.last_used_at
    access_token.touch_last_used!
    assert_not_nil access_token.reload.last_used_at
  end

  test "active scope returns only active tokens" do
    active_token = create(:access_token)
    inactive_token = create(:access_token, :inactive)

    active_tokens = AccessToken.active
    assert_includes active_tokens, active_token
    assert_not_includes active_tokens, inactive_token
  end

  test "sets default is_active to true" do
    token = AccessToken.new
    assert token.is_active?
  end

  test "generates ~260 character token" do
    token = create(:access_token)
    assert token.token.length >= 250
    assert token.token.length <= 270
  end

  test "validates user tokens limit" do
    user = create(:user)
    20.times { create(:access_token, user: user) }

    new_token = build(:access_token, user: user)
    assert_not new_token.valid?
    assert_includes new_token.errors[:user], "cannot have more than 20 access tokens"
  end
end
