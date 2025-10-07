require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "authenticated? returns true when user is signed in" do
    user = create(:user)
    login_as(user)
    follow_redirect!

    get feeds_path
    assert_response :success
  end

  test "require_authentication redirects when not signed in" do
    get feeds_path
    assert_redirected_to new_session_path
  end

  test "update_session_activity touches session after 10 minutes" do
    user = create(:user)
    login_as(user)
    session = user.sessions.last

    session.update_column(:updated_at, 11.minutes.ago)

    get feeds_path
    assert_response :success

    assert session.reload.updated_at > 1.minute.ago
  end

  test "update_session_activity does not touch recent session" do
    user = create(:user)
    login_as(user)
    session = user.sessions.last

    session.update_column(:updated_at, 5.minutes.ago)
    old_timestamp = session.updated_at

    get feeds_path
    assert_response :success

    assert_equal old_timestamp.to_i, session.reload.updated_at.to_i
  end

  test "terminates session and redirects when user is suspended" do
    user = create(:user)
    login_as(user)
    follow_redirect!

    # Verify user is signed in
    get feeds_path
    assert_response :success

    # Suspend the user
    user.update!(suspended_at: Time.current)

    # Next request should terminate session and redirect
    get feeds_path
    assert_redirected_to new_session_path
    assert_equal "Your account has been suspended.", flash[:alert]

    # Verify session was destroyed
    assert_equal 0, user.sessions.count
  end

  private

  def login_as(user)
    post session_url, params: { email_address: user.email_address, password: "password123" }
  end
end
