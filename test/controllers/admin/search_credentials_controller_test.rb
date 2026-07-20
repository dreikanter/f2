require "test_helper"

class Admin::SearchCredentialsControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= begin
      user = create(:user)
      create(:permission, user: user, name: "admin")
      user
    end
  end

  def search_credential
    @search_credential ||= create(:search_credential, :active)
  end

  test "#show should redirect non-admin users" do
    sign_in_as(create(:user))

    get admin_search_credential_path(search_credential)

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "#show should redirect unauthenticated users" do
    get admin_search_credential_path(search_credential)

    assert_redirected_to new_session_path
  end

  test "#show should display another user's credential with an owner link" do
    sign_in_as(admin_user)

    get admin_search_credential_path(search_credential)

    assert_response :success
    assert_select "h1", search_credential.display_name
    assert_select "a[href=?]", admin_user_path(search_credential.user), text: search_credential.user.email_address
    assert_select "a[href=?]", admin_path, text: "Admin Panel"
    assert_select "[data-key='search_credential.active']"
    assert_select "[data-key='search_credential.usage']"
  end

  test "#show should not expose the API key or management actions" do
    sign_in_as(admin_user)

    get admin_search_credential_path(search_credential)

    assert_response :success
    assert_no_match search_credential.credential_data["api_key"], response.body
    assert_select "a[href=?]", edit_search_credential_path(search_credential), count: 0
    assert_no_match "Delete…", response.body
    assert_select "[data-key='admin.search_credential.show'] a[href=?]", search_credentials_path, count: 0
  end
end
