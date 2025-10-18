require "test_helper"

class OnboardingsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user, :with_onboarding)
  end

  test "should show onboarding page when authenticated and onboarding exists" do
    sign_in_as(user)
    get onboarding_url
    assert_response :success
  end

  test "should destroy onboarding" do
    sign_in_as(user)
    assert_not_nil user.onboarding

    delete onboarding_url
    assert_nil user.reload.onboarding
    assert_redirected_to status_path
  end

  test "should require authentication to access onboarding" do
    get onboarding_url
    assert_redirected_to new_session_path
  end
end
