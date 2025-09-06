require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def sign_in_user
    post session_url, params: { email_address: user.email_address, password: "password123" }
  end

  test "should show profile when authenticated" do
    sign_in_user
    get profile_url
    assert_response :success
  end

  test "should redirect to login when not authenticated" do
    get profile_url
    assert_redirected_to new_session_path
  end
end
