require "test_helper"

class OnboardingsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user, :with_onboarding)
  end

  def sign_in_as(user)
    post session_url, params: { email_address: user.email_address, password: "password123" }
  end

  test "should show onboarding page when authenticated and onboarding exists" do
    sign_in_as(user)
    get onboarding_url
    assert_response :success
  end

  test "should redirect to onboarding when session flag is set" do
    user_without_onboarding = create(:user)
    sign_in_as(user_without_onboarding)

    # Create onboarding
    post onboarding_url
    follow_redirect!
    assert_equal onboarding_path, path

    # Try to access another page
    get feeds_path
    assert_redirected_to onboarding_path
  end

  test "should not redirect to onboarding when session flag is not set" do
    user_without_onboarding = create(:user)
    sign_in_as(user_without_onboarding)

    get feeds_path
    assert_response :success
  end

  test "should create onboarding and set session flag" do
    user_without_onboarding = create(:user)
    sign_in_as(user_without_onboarding)

    assert_nil user_without_onboarding.reload.onboarding

    post onboarding_url
    assert_not_nil user_without_onboarding.reload.onboarding
    assert session[:onboarding]
    assert_redirected_to onboarding_path
  end

  test "should destroy onboarding and clear session flag" do
    sign_in_as(user)
    assert_not_nil user.onboarding

    delete onboarding_url
    assert_nil user.reload.onboarding
    assert_not session[:onboarding]
    assert_redirected_to status_path
  end

  test "should set session flag on sign in when onboarding exists" do
    user_with_onboarding = create(:user, :with_onboarding)
    post session_url, params: { email_address: user_with_onboarding.email_address, password: "password123" }
    assert session[:onboarding]
  end

  test "should not set session flag on sign in when onboarding does not exist" do
    user_without_onboarding = create(:user)
    post session_url, params: { email_address: user_without_onboarding.email_address, password: "password123" }
    assert_not session[:onboarding]
  end

  test "should require authentication to access onboarding" do
    get onboarding_url
    assert_redirected_to new_session_path
  end
end
