require "test_helper"

class CurrentTest < ActiveSupport::TestCase
  test "should delegate user to session" do
    user = create(:user)
    session = create(:session, user: user)

    Current.session = session
    assert_equal user, Current.user
  end

  test "should return nil user when no session" do
    Current.session = nil
    assert_nil Current.user
  end

  test "should allow setting session" do
    session = create(:session)
    Current.session = session
    assert_equal session, Current.session
  end
end
