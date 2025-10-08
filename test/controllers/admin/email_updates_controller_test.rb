require "test_helper"

class Admin::EmailUpdatesControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= create(:user, :admin)
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "should redirect non-admin users from edit" do
    login_as(regular_user)
    user = create(:user)

    get edit_admin_user_email_update_path(user)

    assert_redirected_to root_path
  end

  test "should allow admin users to view email update form" do
    login_as(admin_user)
    user = create(:user, email_address: "test@example.com")

    get edit_admin_user_email_update_path(user)

    assert_response :success
    assert_select "h1", "Change Email for test@example.com"
    assert_select "input[type='checkbox'][name='require_confirmation']"
  end

  test "should update email for user without confirmation" do
    login_as(admin_user)
    user = create(:user, email_address: "old@example.com")

    patch admin_user_email_update_path(user), params: { user: { email_address: "new@example.com" }, require_confirmation: "0" }

    assert_redirected_to admin_user_path(user)
    assert_equal "Email address updated successfully.", flash[:notice]
    assert_equal "new@example.com", user.reload.email_address
  end

  test "should send confirmation email when checkbox is checked" do
    login_as(admin_user)
    user = create(:user, email_address: "old@example.com")

    assert_enqueued_emails 1 do
      patch admin_user_email_update_path(user), params: { user: { email_address: "new@example.com" }, require_confirmation: "1" }
    end

    assert_redirected_to admin_user_path(user)
    assert_equal "Confirmation email sent to new@example.com. User must confirm before change takes effect.", flash[:notice]
    assert_equal "old@example.com", user.reload.email_address
  end

  test "should reject blank email" do
    login_as(admin_user)
    user = create(:user, email_address: "test@example.com")

    patch admin_user_email_update_path(user), params: { user: { email_address: "" } }

    assert_redirected_to edit_admin_user_email_update_path(user)
    assert_equal "Email address cannot be blank.", flash[:alert]
    assert_equal "test@example.com", user.reload.email_address
  end

  test "should reject same email" do
    login_as(admin_user)
    user = create(:user, email_address: "test@example.com")

    patch admin_user_email_update_path(user), params: { user: { email_address: "test@example.com" } }

    assert_redirected_to edit_admin_user_email_update_path(user)
    assert_equal "New email is the same as the current email.", flash[:alert]
  end

  test "should reject duplicate email" do
    login_as(admin_user)
    existing_user = create(:user, email_address: "existing@example.com")
    user = create(:user, email_address: "test@example.com")

    patch admin_user_email_update_path(user), params: { user: { email_address: "existing@example.com" } }

    assert_redirected_to edit_admin_user_email_update_path(user)
    assert_equal "Email address is already taken.", flash[:alert]
    assert_equal "test@example.com", user.reload.email_address
  end

  private

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password1234567890" }
  end
end
