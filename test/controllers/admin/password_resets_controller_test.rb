require "test_helper"

class Admin::PasswordResetsControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= create(:user, :admin)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "should redirect non-admin users from show" do
    login_as(regular_user)
    user = create(:user)

    get admin_user_password_reset_path(user)

    assert_redirected_to root_path
  end

  test "should redirect non-admin users from create" do
    login_as(regular_user)
    user = create(:user)

    post admin_user_password_reset_path(user)

    assert_redirected_to root_path
  end

  test "should allow admin users to view password reset confirmation" do
    login_as(admin_user)
    user = create(:user, email_address: "test@example.com")

    get admin_user_password_reset_path(user)

    assert_response :success
    assert_select "h1", "Reset Password for test@example.com"
  end

  test "should send password reset email" do
    login_as(admin_user)
    user = create(:user, email_address: "test@example.com")

    assert_enqueued_emails 1 do
      post admin_user_password_reset_path(user)
    end

    assert_redirected_to admin_user_path(user)
    assert_equal "Password reset email sent to test@example.com.", flash[:notice]
  end

  private

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password1234567890" }
  end
end
