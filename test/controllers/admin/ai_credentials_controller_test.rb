require "test_helper"

class Admin::AiCredentialsControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= begin
      user = create(:user)
      create(:permission, user: user, name: "admin")
      user
    end
  end

  def ai_credential
    @ai_credential ||= create(:ai_credential, :active)
  end

  test "#show should redirect non-admin users" do
    sign_in_as(create(:user))

    get admin_ai_credential_path(ai_credential)

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "#show should redirect unauthenticated users" do
    get admin_ai_credential_path(ai_credential)

    assert_redirected_to new_session_path
  end

  test "#show should display another user's credential with an owner link" do
    sign_in_as(admin_user)

    get admin_ai_credential_path(ai_credential)

    assert_response :success
    assert_select "h1", ai_credential.display_name
    assert_select "a[href=?]", admin_user_path(ai_credential.user), text: ai_credential.user.email_address
    assert_select "a[href=?]", admin_path, text: "Admin Panel"
    assert_select "[data-key='ai_credential.active']"
    assert_select "[data-key='ai_credential.provider']"
  end

  test "#show should not expose the API key or management actions" do
    sign_in_as(admin_user)

    get admin_ai_credential_path(ai_credential)

    assert_response :success
    assert_no_match ai_credential.credential_data["api_key"], response.body
    assert_select "a[href=?]", edit_ai_credential_path(ai_credential), count: 0
    assert_no_match "Delete…", response.body
    assert_select "[data-key='admin.ai_credential.show'] a[href=?]", ai_credentials_path, count: 0
  end

  test "#show should surface the last error for an inactive credential" do
    sign_in_as(admin_user)
    credential = create(:ai_credential, :inactive)

    get admin_ai_credential_path(credential)

    assert_response :success
    assert_select "[data-key='ai_credential.inactive']", text: /Invalid API key/
  end
end
