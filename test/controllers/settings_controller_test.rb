require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= regular_user
  end

  test "should show settings when authenticated" do
    sign_in_as(user)
    get settings_url
    assert_response :success
    assert_select "h2", text: "Your Name"
    assert_select "h2", text: "Change Email"
    assert_select "h2", text: "Change Password"
    assert_select "h2", text: "FreeFeed Application Tokens", count: 0
    assert_select "h2", text: "Feeder Invites", count: 0
  end

  test "should show current email and password age in account cards" do
    sign_in_as(user)
    get settings_url
    assert_response :success
    assert_select "[data-key='settings.email'] p", text: "Your current email is #{user.email_address}"
    assert_select "[data-key='settings.password'] p", text: /\ALast changed .+ ago\z/
  end

  test "should describe the name card" do
    sign_in_as(user)
    get settings_url
    assert_response :success
    assert_select "[data-key='settings.name'] p", text: "The name people you invite will see"
  end

  test "should link to settings sections" do
    sign_in_as(user)
    get settings_url
    assert_response :success
    assert_select "a[href=?]", edit_settings_name_update_path
    assert_select "a[href=?]", edit_settings_email_update_path
    assert_select "a[href=?]", edit_settings_password_update_path
    assert_select "a[href=?]", access_tokens_path
    assert_select "a[href=?]", ai_credentials_path
    assert_select "a[href=?]", search_credentials_path, count: 0
    assert_select "a[href=?]", invites_path
  end

  test "should redirect to login when not authenticated" do
    get settings_url
    assert_redirected_to new_session_path
  end

  test "should expose search credentials when external search is enabled" do
    sign_in_as(user)

    Rails.configuration.x.stub(:external_search_enabled, true) do
      get settings_url
    end

    assert_select "a[href=?]", search_credentials_path
    assert_select "h2", text: "Search Credentials"
  end

  test "should show permission display name in the page header" do
    @user = create(:user, :dev)
    sign_in_as(user)
    get settings_url
    assert_response :success
    assert_select "header [data-key='settings.permissions.value']", text: "Developer Tools"
  end

  test "should not show permissions when the user has none" do
    sign_in_as(user)
    get settings_url
    assert_response :success
    assert_select "[data-key='settings.permissions.value']", count: 0
  end
end
