require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "should be valid with email and password" do
    user = User.new(email_address: "test@example.com", password: "password", password_confirmation: "password")
    assert user.valid?
  end

  test "should require email address" do
    user = User.new(password: "password", password_confirmation: "password")
    assert_not user.valid?
    assert user.errors.of_kind?(:email_address, :blank)
  end

  test "should require unique email address" do
    existing_user = users(:one)
    user = User.new(email_address: existing_user.email_address, password: "password", password_confirmation: "password")
    assert_not user.valid?
    assert user.errors.of_kind?(:email_address, :taken)
  end

  test "should authenticate with correct password" do
    user = users(:one)
    assert user.authenticate("password")
  end

  test "should not authenticate with wrong password" do
    user = users(:one)
    assert_not user.authenticate("wrong_password")
  end

  test "should authenticate by email and password" do
    user = users(:one)
    authenticated_user = User.authenticate_by(email_address: user.email_address, password: "password")
    assert_equal user, authenticated_user
  end

  test "should not authenticate with wrong email or password" do
    authenticated_user = User.authenticate_by(email_address: "wrong@example.com", password: "password")
    assert_nil authenticated_user
  end
end
