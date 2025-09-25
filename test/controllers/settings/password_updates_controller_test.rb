require "test_helper"

class Settings::PasswordUpdatesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def sign_in_user
    post session_url, params: { email_address: user.email_address, password: "password123" }
  end

  test "should redirect to login when not authenticated" do
    patch settings_password_update_url, params: {
      user: {
        current_password: "password123",
        password: "new123",
        password_confirmation: "new123"
      }
    }
    assert_redirected_to new_session_path
  end

  test "should update password with correct current password" do
    sign_in_user
    patch settings_password_update_url, params: {
      user: {
        current_password: "password123",
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }
    assert_redirected_to settings_path
    assert_equal "Password updated successfully.", flash[:notice]
  end

  test "should not update password with incorrect current password" do
    sign_in_user
    patch settings_password_update_url, params: {
      user: {
        current_password: "wrongpassword",
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }
    assert_redirected_to edit_settings_password_update_path
    assert_equal "Current password is incorrect.", flash[:alert]
  end

  test "should not update password with mismatched confirmation" do
    sign_in_user
    patch settings_password_update_url, params: {
      user: {
        current_password: "password123",
        password: "newpassword123",
        password_confirmation: "different123"
      }
    }
    assert_redirected_to edit_settings_password_update_path
    assert_match "Password confirmation doesn't match", flash[:alert]
  end
end
