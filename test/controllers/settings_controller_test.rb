require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def sign_in_user
    post session_url, params: { email_address: user.email_address, password: "password123" }
  end

  test "should show settings when authenticated" do
    sign_in_user
    get settings_url
    assert_response :success
    assert_select "h2", text: "Your Account"
    assert_select "h2", text: "FreeFeed Application Tokens", count: 0
    assert_select "h2", text: "Feeder Invites", count: 0
  end

  test "should link to settings sections" do
    sign_in_user
    get settings_url
    assert_response :success
    assert_select "a[href=?]", access_tokens_path
    assert_select "a[href=?]", ai_credentials_path
    assert_select "a[href=?]", invites_path
  end

  test "should redirect to login when not authenticated" do
    get settings_url
    assert_redirected_to new_session_path
  end
end
