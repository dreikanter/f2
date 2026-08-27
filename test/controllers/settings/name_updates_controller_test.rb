require "test_helper"

class Settings::NameUpdatesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user, name: "Original Name")
  end

  def sign_in_user
    post session_url, params: { email_address: user.email_address, password: "password123" }
  end

  test "should redirect to login when not authenticated" do
    get edit_settings_name_update_url
    assert_redirected_to new_session_path
  end

  test "should redirect to login when updating without authentication" do
    patch settings_name_update_url, params: { user: { name: "Alex" } }
    assert_redirected_to new_session_path
    assert_equal "Original Name", user.reload.name
  end

  test "should show the current name in the form" do
    sign_in_user
    get edit_settings_name_update_url
    assert_response :success
    assert_select "input[name='user[name]'][value=?]", "Original Name"
    assert_select "[data-key='name_update.hint']", text: /Somebody/
  end

  test "should update the name" do
    sign_in_user
    patch settings_name_update_url, params: { user: { name: "Alex" } }
    assert_redirected_to settings_path
    assert_equal "Name updated.", flash[:success]
    assert_equal "Alex", user.reload.name
  end

  test "should allow clearing the name" do
    sign_in_user
    patch settings_name_update_url, params: { user: { name: "" } }
    assert_redirected_to settings_path
    assert_equal "", user.reload.name
  end

  test "should reject a name longer than the limit" do
    sign_in_user
    patch settings_name_update_url, params: { user: { name: "a" * (User::NAME_MAX_LENGTH + 1) } }
    assert_redirected_to edit_settings_name_update_path
    assert_match "too long", flash[:alert]
    assert_equal "Original Name", user.reload.name
  end

  test "should treat a missing name param as blank" do
    sign_in_user
    patch settings_name_update_url
    assert_redirected_to settings_path
    assert_equal "", user.reload.name
  end
end
