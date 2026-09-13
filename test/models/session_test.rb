require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "#valid? should return true with user" do
    session = build(:session)
    assert session.valid?
  end

  test "#valid? should require user" do
    session = build(:session, user: nil)
    assert_not session.valid?
    assert session.errors.of_kind?(:user, :blank)
  end

  test "#user should return the associated user" do
    user = create(:user)
    session = create(:session, user: user)
    assert_equal user, session.user
  end

  test "#valid? should allow optional ip_address and user_agent" do
    session = build(:session, ip_address: nil, user_agent: nil)
    assert session.valid?
  end

  test "#destroy should remove the user's sessions" do
    user = create(:user)
    session = create(:session, user: user)

    assert_difference "Session.count", -1 do
      user.destroy
    end
  end

  test ".find_active should expire sessions strictly past the inactivity timeout" do
    freeze_time do
      active = create(:session, last_seen_at: 1.day.ago)
      boundary = create(:session, last_seen_at: Session::INACTIVITY_TIMEOUT.ago)
      expired = create(:session, last_seen_at: Session::INACTIVITY_TIMEOUT.ago - 1.second)

      assert_equal active, Session.find_active(active.id)
      assert_equal boundary, Session.find_active(boundary.id)
      assert_nil Session.find_active(expired.id)
      assert_nil Session.find_active(nil)
    end
  end

  test "#create should record login activity on the session and user" do
    freeze_time do
      session = create(:session, last_seen_at: nil)

      assert_equal Time.current, session.last_seen_at
      assert_equal Time.current, session.user.reload.last_seen_at
    end
  end

  test "#record_user_activity should preserve the latest activity across sessions" do
    user = create(:user, last_seen_at: 1.hour.ago)
    old_updated_at = user.updated_at
    session = create(:session, user: user, last_seen_at: 1.day.ago)

    assert_in_delta 1.hour.ago, user.reload.last_seen_at, 1.second

    freeze_time do
      session.update!(last_seen_at: Time.current)
      assert_equal Time.current, user.reload.last_seen_at
      assert_equal old_updated_at, user.updated_at
    end
  end
end
