require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "#authenticated? should return true when user is signed in" do
    user = create(:user)
    sign_in_as(user)
    follow_redirect!

    get feeds_path
    assert_response :success
  end

  test "#require_authentication should redirect when not signed in" do
    get feeds_path
    assert_redirected_to new_session_path
  end

  test "#update_session_activity should touch session after 10 minutes" do
    user = create(:user)
    sign_in_as(user)
    session = user.sessions.last

    session.update_column(:last_seen_at, 11.minutes.ago)

    get feeds_path, headers: { "User-Agent" => "Current Browser" }
    assert_response :success

    assert session.reload.last_seen_at > 1.minute.ago
    assert_equal "Current Browser", session.user_agent
    assert_equal session.last_seen_at, user.reload.last_seen_at
  end

  test "#update_session_activity should not touch recent session" do
    user = create(:user)
    sign_in_as(user)
    session = user.sessions.last

    session.update_column(:last_seen_at, 5.minutes.ago)
    old_timestamp = session.last_seen_at

    get feeds_path
    assert_response :success

    assert_equal old_timestamp.to_i, session.reload.last_seen_at.to_i
  end

  test "#terminate_session should preserve the user last seen after logout" do
    user = create(:user)
    sign_in_as(user)
    session = user.sessions.last

    last_seen_at = session.last_seen_at
    assert_equal last_seen_at, user.reload.last_seen_at

    delete session_path

    assert_not Session.exists?(session.id)
    assert_equal last_seen_at, user.reload.last_seen_at
  end

  test "#require_authentication should reject a session past the inactivity timeout" do
    user = create(:user)
    sign_in_as(user)
    user.sessions.last.update_column(:last_seen_at, Session::INACTIVITY_TIMEOUT.ago - 1.minute)

    get feeds_path

    assert_redirected_to new_session_path
  end
end
