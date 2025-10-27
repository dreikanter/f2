require "test_helper"

class Registration::EmailConfirmationsControllerTest < ActionDispatch::IntegrationTest
  test "should activate inactive user with valid confirmation token" do
    inactive_user = create(:user, state: :inactive)
    token = inactive_user.generate_token_for(:initial_email_confirmation)

    get registration_email_confirmation_url(token)

    assert_redirected_to new_session_path
    assert_equal "Your email is now confirmed. Please sign in to get started.", flash[:notice]
    assert inactive_user.reload.onboarding?
  end

  test "should redirect to login with invalid confirmation token" do
    get registration_email_confirmation_url("invalid")

    assert_redirected_to new_session_path
    assert_equal "Email confirmation link is invalid or has expired.", flash[:alert]
  end

  test "should not change state of already onboarding user" do
    onboarding_user = create(:user, state: :onboarding)
    token = onboarding_user.generate_token_for(:initial_email_confirmation)

    get registration_email_confirmation_url(token)

    assert_redirected_to new_session_path
    assert onboarding_user.reload.onboarding?
  end
end
