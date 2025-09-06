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
    assert_select "h4", "Profile"
  end

  test "should redirect to login when not authenticated" do
    get profile_url
    assert_redirected_to new_session_path
  end



  test "should update password with correct current password" do
    sign_in_user
    patch profile_url, params: {
      commit: "Change Password",
      user: {
        current_password: "password123",
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }
    assert_redirected_to profile_path
    assert_equal "Password updated successfully.", flash[:notice]
  end

  test "should not update password with incorrect current password" do
    sign_in_user
    patch profile_url, params: {
      commit: "Change Password",
      user: {
        current_password: "wrongpassword",
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }
    assert_redirected_to profile_path
    assert_equal "Current password is incorrect.", flash[:alert]
  end

  test "should request email confirmation for email change" do
    sign_in_user
    assert_emails 1 do
      patch profile_url, params: {
        commit: "Update Email",
        user: { email_address: "newemail@example.com" }
      }
    end
    assert_redirected_to profile_path
    assert_match "Email confirmation sent", flash[:notice]
  end

  test "should not allow duplicate email address" do
    existing_user = create(:user, email_address: "taken@example.com")
    sign_in_user

    patch profile_url, params: {
      commit: "Update Email",
      user: { email_address: "taken@example.com" }
    }
    assert_redirected_to profile_path
    assert_equal "Email address is already taken.", flash[:alert]
  end
end
