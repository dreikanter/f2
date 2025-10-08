require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def sign_in_user
    post session_url, params: { email_address: user.email_address, password: "password1234567890" }
  end

  test "should show settings when authenticated" do
    sign_in_user
    get settings_url
    assert_response :success
  end

  test "should redirect to login when not authenticated" do
    get settings_url
    assert_redirected_to new_session_path
  end
end
