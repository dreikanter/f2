require "test_helper"

class EmailConfirmationsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def sign_in_user
    post session_url, params: { email_address: user.email_address, password: "password123" }
  end

  test "should confirm email change with valid token" do
    sign_in_user
    token = user.generate_token_for(:email_change)
    new_email = "updated@example.com"

    get email_confirmation_url(token), params: { new_email: new_email }

    assert_redirected_to profile_path
    assert_equal "Email address successfully updated to #{new_email}.", flash[:notice]
    assert_equal new_email, user.reload.email_address
  end

  test "should reject invalid token" do
    sign_in_user
    get email_confirmation_url("invalid"), params: { new_email: "new@example.com" }

    assert_redirected_to profile_path
    assert_equal "Email confirmation link is invalid or has expired.", flash[:alert]
  end

  test "should reject email change to existing email" do
    existing_user = create(:user, email_address: "taken@example.com")
    sign_in_user
    token = user.generate_token_for(:email_change)

    get email_confirmation_url(token), params: { new_email: "taken@example.com" }

    assert_redirected_to profile_path
    assert_equal "Email confirmation failed. The email may already be taken.", flash[:alert]
  end
end
