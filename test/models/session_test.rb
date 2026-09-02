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

  test ".active should include established and newly issued sessions within the inactivity timeout" do
    established = create(:session, last_seen_at: 1.day.ago)
    issued = create(:session, last_seen_at: nil)
    create(:session, last_seen_at: Session::INACTIVITY_TIMEOUT.ago - 1.minute)
    create(:session, last_seen_at: nil, created_at: Session::INACTIVITY_TIMEOUT.ago - 1.minute)

    assert_equal [established.id, issued.id].sort, Session.active.pluck(:id).sort
  end

  test ".established should exclude sessions whose cookie was never used" do
    established = create(:session)
    create(:session, last_seen_at: nil)

    assert_equal [established], Session.established.to_a
  end

  test ".find_active should return only a session within the inactivity timeout" do
    active = create(:session, last_seen_at: 1.day.ago)
    issued = create(:session, last_seen_at: nil)
    expired = create(:session, last_seen_at: Session::INACTIVITY_TIMEOUT.ago - 1.minute)

    assert_equal active, Session.find_active(active.id)
    assert_equal issued, Session.find_active(issued.id)
    assert_nil Session.find_active(expired.id)
    assert_nil Session.find_active(nil)
  end
end
