require "test_helper"

class Settings::EmailConfirmationsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def sign_in_user
    params = {
      email_address: user.email_address,
      password: "password123"
    }

    post session_url, params: params
  end

  test "should confirm email change with valid token" do
    sign_in_user
    new_email = "updated@example.com"
    user.update!(unconfirmed_email: new_email)
    token = user.generate_token_for(:change_email_confirmation)

    get settings_email_confirmation_url(token)

    assert_redirected_to settings_path
    assert_equal "Email address successfully updated.", flash[:notice]
    assert_equal new_email, user.reload.email_address
    assert_nil user.unconfirmed_email
  end

  test "should reject invalid token" do
    sign_in_user
    get settings_email_confirmation_url("invalid")

    assert_redirected_to settings_path
    assert_equal "Email confirmation link is invalid or has expired.", flash[:alert]
  end

  test "should reject email change to existing email in race condition" do
    sign_in_user
    # Set unconfirmed_email bypassing validation to simulate race condition
    user.update_column(:unconfirmed_email, "race@example.com")
    token = user.generate_token_for(:change_email_confirmation)

    # Another user claims the email before confirmation
    create(:user, email_address: "race@example.com")

    get settings_email_confirmation_url(token)

    assert_redirected_to settings_path
    assert_equal "Email confirmation failed. Please request a new confirmation link.", flash[:alert]
  end
end
