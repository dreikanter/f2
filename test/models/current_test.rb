require "test_helper"

class CurrentTest < ActiveSupport::TestCase
  test ".user should return the session user" do
    user = create(:user)
    session = create(:session, user: user)

    Current.session = session
    assert_equal user, Current.user
  end

  test ".user should return nil when there is no session" do
    Current.session = nil
    assert_nil Current.user
  end

  test ".session= should store the current session" do
    session = create(:session)
    Current.session = session
    assert_equal session, Current.session
  end
end
