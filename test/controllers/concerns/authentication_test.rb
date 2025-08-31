require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "authenticated? returns true when user is signed in" do
    user = create(:user)
    post session_url, params: { email_address: user.email_address, password: "password123" }
    follow_redirect!

    # Now test a protected action
    get feeds_path
    assert_response :success
  end

  test "require_authentication redirects when not signed in" do
    get feeds_path
    assert_redirected_to new_session_path
  end
end
