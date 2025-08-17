require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "should be valid with user" do
    session = build(:session)
    assert session.valid?
  end

  test "should require user" do
    session = build(:session, user: nil)
    assert_not session.valid?
    assert session.errors.of_kind?(:user, :blank)
  end

  test "should belong to user" do
    user = create(:user)
    session = create(:session, user: user)
    assert_equal user, session.user
  end

  test "should allow optional ip_address and user_agent" do
    session = build(:session, ip_address: nil, user_agent: nil)
    assert session.valid?
  end

  test "should be destroyed when user is destroyed" do
    user = create(:user)
    session = create(:session, user: user)

    assert_difference "Session.count", -1 do
      user.destroy
    end
  end
end
