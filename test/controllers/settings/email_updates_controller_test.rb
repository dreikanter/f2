require "test_helper"

class Settings::EmailUpdatesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def sign_in_user
    post session_url, params: { email_address: user.email_address, password: "password123" }
  end

  test "should redirect to login when not authenticated" do
    patch settings_email_update_url, params: { user: { email_address: "new@example.com" } }
    assert_redirected_to new_session_path
  end

  test "should request email confirmation for valid email change" do
    sign_in_user
    assert_emails 1 do
      patch settings_email_update_url, params: { user: { email_address: "newemail@example.com" } }
    end
    assert_redirected_to settings_path
    assert_match "Email confirmation sent", flash[:notice]
  end

  test "should not allow duplicate email address" do
    create(:user, email_address: "taken@example.com")
    sign_in_user

    patch settings_email_update_url, params: { user: { email_address: "taken@example.com" } }
    assert_redirected_to edit_settings_email_update_path
    assert_equal "Email address is already taken.", flash[:alert]
  end

  test "should reject empty email" do
    sign_in_user
    patch settings_email_update_url, params: { user: { email_address: "" } }
    assert_redirected_to edit_settings_email_update_path
    assert_equal "Please enter a valid new email address.", flash[:alert]
  end

  test "should reject same email as current" do
    sign_in_user
    patch settings_email_update_url, params: { user: { email_address: user.email_address } }
    assert_redirected_to edit_settings_email_update_path
    assert_equal "Please enter a valid new email address.", flash[:alert]
  end

  test "should allow email change when no recent email change event exists" do
    sign_in_user

    assert user.can_change_email?

    patch settings_email_update_url, params: { user: { email_address: "new@example.com" } }
    assert_redirected_to settings_path
  end

  test "should reject email change when rate limited" do
    sign_in_user
    Event.create!(
      type: "email_changed",
      level: :info,
      subject: user,
      user: user,
      message: "Email changed from old@example.com to #{user.email_address}",
      metadata: { old_email: "old@example.com", new_email: user.email_address }
    )

    assert_not user.can_change_email?

    patch settings_email_update_url, params: { user: { email_address: "new@example.com" } }
    assert_redirected_to edit_settings_email_update_path
    assert_match /You can change your email again in/, flash[:alert]
  end

  test "should allow email change after rate limit expires" do
    sign_in_user
    travel_to 25.hours.ago do
      Event.create!(
        type: "email_changed",
        level: :info,
        subject: user,
        user: user,
        message: "Email changed from old@example.com to #{user.email_address}",
        metadata: { old_email: "old@example.com", new_email: user.email_address }
      )
    end

    assert user.can_change_email?

    patch settings_email_update_url, params: { user: { email_address: "new@example.com" } }
    assert_redirected_to settings_path
  end
end
