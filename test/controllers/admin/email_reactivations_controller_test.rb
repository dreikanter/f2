require "test_helper"

class Admin::EmailReactivationsControllerTest < ActionDispatch::IntegrationTest
  test "should allow admin to reactivate user email" do
    sign_in_as(admin_user)
    user = create(:user)
    user.deactivate_email!(reason: "bounced")

    assert user.email_deactivated?

    post admin_user_email_reactivation_path(user)

    user.reload
    assert_not user.email_deactivated?
    assert_nil user.email_deactivation_reason
    assert_redirected_to admin_user_path(user)
    follow_redirect!
    assert_select "[role=\"alert\"]", text: /Email reactivated/
  end

  test "should prevent non-admin from reactivating user email" do
    sign_in_as(regular_user)
    user = create(:user)
    user.deactivate_email!(reason: "bounced")

    post admin_user_email_reactivation_path(user)

    assert_redirected_to root_path
    user.reload
    assert user.email_deactivated?
  end
end
