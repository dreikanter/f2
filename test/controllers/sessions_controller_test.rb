require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get new_session_url
    assert_response :success
  end

  test "should create session with valid credentials" do
    user = users(:one)

    post session_url, params: { email_address: user.email_address, password: "password" }
    assert_redirected_to root_url
  end

  test "should not create session with invalid credentials" do
    post session_url, params: { email_address: "wrong@example.com", password: "wrong" }
    assert_redirected_to new_session_path
  end

  test "should destroy session" do
    user = create(:user)

    # Create session by signing in
    post session_url, params: { email_address: user.email_address, password: "password123" }
    follow_redirect!

    # Verify we have a session by checking we can access protected resource
    get feeds_path
    assert_response :success

    delete session_url
    assert_redirected_to new_session_path

    # Verify session was destroyed by trying to access protected resource
    get feeds_path
    assert_redirected_to new_session_path
  end

  test "should redirect to requested page after authentication" do
    # Try to access protected page without authentication
    get feeds_path
    assert_redirected_to new_session_path

    # Sign in
    user = create(:user)
    post session_url, params: { email_address: user.email_address, password: "password123" }

    # Should redirect back to the originally requested page
    assert_redirected_to feeds_path
  end

  test "should not create session for suspended user" do
    user = create(:user)
    user.suspend!

    post session_url, params: { email_address: user.email_address, password: "password123" }

    assert_redirected_to new_session_path
    assert_equal "Your account has been suspended.", flash[:alert]
  end

  test "should not create session for inactive user" do
    user = create(:user, state: :inactive)

    post session_url, params: { email_address: user.email_address, password: "password123" }

    assert_redirected_to new_session_path
    assert_equal "Email confirmation is required. Please check your inbox.", flash[:alert]
  end

  test "should terminate all sessions when inactive user attempts login" do
    user = create(:user, state: :inactive)
    user.sessions.create!(user_agent: "Browser", ip_address: "1.1.1.1")

    assert_equal 1, user.sessions.count

    post session_url, params: { email_address: user.email_address, password: "password123" }

    assert_equal 0, user.reload.sessions.count
  end
end
