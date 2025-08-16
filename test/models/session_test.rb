require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "should be valid with user" do
    user = users(:one)
    session = Session.new(user: user, ip_address: "127.0.0.1", user_agent: "Test Browser")
    assert session.valid?
  end

  test "should require user" do
    session = Session.new(ip_address: "127.0.0.1", user_agent: "Test Browser")
    assert_not session.valid?
    assert session.errors.of_kind?(:user, :blank)
  end

  test "should belong to user" do
    user = users(:one)
    session = Session.create!(user: user, ip_address: "127.0.0.1", user_agent: "Test Browser")
    assert_equal user, session.user
  end

  test "should allow optional ip_address and user_agent" do
    user = users(:one)
    session = Session.new(user: user)
    assert session.valid?
  end

  test "should be destroyed when user is destroyed" do
    user = users(:one)
    session = Session.create!(user: user, ip_address: "127.0.0.1", user_agent: "Test Browser")
    
    assert_difference "Session.count", -1 do
      user.destroy
    end
  end
end