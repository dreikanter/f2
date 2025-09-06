require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "should be valid with email and password" do
    user = build(:user)
    assert user.valid?
  end

  test "should require email address" do
    user = build(:user, email_address: nil)
    assert_not user.valid?
    assert user.errors.of_kind?(:email_address, :blank)
  end

  test "should require unique email address" do
    existing_user = create(:user)
    user = build(:user, email_address: existing_user.email_address)
    assert_not user.valid?
    assert user.errors.of_kind?(:email_address, :taken)
  end

  test "should authenticate with correct password" do
    user = create(:user)
    assert user.authenticate("password123")
  end

  test "should not authenticate with wrong password" do
    user = create(:user)
    assert_not user.authenticate("wrong_password")
  end

  test "should authenticate by email and password" do
    user = create(:user)
    authenticated_user = User.authenticate_by(email_address: user.email_address, password: "password123")
    assert_equal user, authenticated_user
  end

  test "should not authenticate with wrong email or password" do
    authenticated_user = User.authenticate_by(email_address: "wrong@example.com", password: "password")
    assert_nil authenticated_user
  end

  test "should have many feeds" do
    user = create(:user)
    feed1 = create(:feed, user: user)
    feed2 = create(:feed, user: user)

    assert_equal 2, user.feeds.count
    assert_includes user.feeds, feed1
    assert_includes user.feeds, feed2
  end

  test "should destroy associated feeds when user is destroyed" do
    user = create(:user)
    create(:feed, user: user)
    create(:feed, user: user)

    assert_difference("Feed.count", -2) do
      user.destroy!
    end
  end

  test "should have many permissions" do
    user = create(:user)
    permission = create(:permission, user: user, name: "admin")

    assert_equal 1, user.permissions.count
    assert_includes user.permissions, permission
  end

  test "should destroy associated permissions when user is destroyed" do
    user = create(:user)
    create(:permission, user: user, name: "admin")

    assert_difference("Permission.count", -1) do
      user.destroy!
    end
  end

  test "should have many access_tokens" do
    user = create(:user)
    token1 = create(:access_token, user: user)
    token2 = create(:access_token, user: user)

    assert_equal 2, user.access_tokens.count
    assert_includes user.access_tokens, token1
    assert_includes user.access_tokens, token2
  end

  test "should destroy associated access_tokens when user is destroyed" do
    user = create(:user)
    create(:access_token, user: user)
    create(:access_token, user: user)

    assert_difference("AccessToken.count", -2) do
      user.destroy!
    end
  end

  test "should validate max access tokens limit" do
    user = create(:user)
    20.times { create(:access_token, user: user) }

    assert_not user.valid?
    assert_includes user.errors[:access_tokens], "cannot exceed 20 tokens per user"
  end
end
