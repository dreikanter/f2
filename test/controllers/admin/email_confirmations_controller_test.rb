require "test_helper"

class Admin::EmailConfirmationsControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= create(:user, :admin)
  end

  test "#create should let an admin confirm a pending user's email" do
    sign_in_as admin_user
    user = create(:user, :inactive)

    post admin_user_email_confirmation_path(user)

    assert_redirected_to admin_user_path(user)
    assert user.reload.active?
    follow_redirect!
    assert_select "[role=\"alert\"]", text: /Email confirmed/
  end

  test "#create should leave an already confirmed user untouched" do
    sign_in_as admin_user
    user = create(:user, state: :active)

    post admin_user_email_confirmation_path(user)

    assert user.reload.active?
  end

  test "#create should require admin permission" do
    sign_in_as create(:user)
    user = create(:user, :inactive)

    post admin_user_email_confirmation_path(user)

    assert_redirected_to root_path
    assert user.reload.inactive?
  end
end
