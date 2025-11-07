require "test_helper"

class Settings::AccessTokensControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user)
  end

  test "requires authentication for index" do
    get settings_access_tokens_path
    assert_redirected_to new_session_path
  end

  test "shows access tokens index when authenticated" do
    sign_in_as user
    get settings_access_tokens_path
    assert_response :success
    assert_select "h1", "Access Tokens"
  end

  test "displays empty state when no tokens" do
    sign_in_as user
    get settings_access_tokens_path
    assert_response :success
    assert_select "h2", "No access tokens yet"
  end

  test "displays existing tokens" do
    sign_in_as user
    access_token
    get settings_access_tokens_path
    assert_response :success
    assert_select '[data-key="settings.access_tokens.table"]'
    assert_select "td", access_token.name
  end

  test "#new should render when authenticated" do
    sign_in_as user
    get new_settings_access_token_path
    assert_response :success
  end

  test "#create should be implemented" do
    skip "TODO: Implement access token creation"
  end

  test "#edit should render for own token" do
    sign_in_as user
    get edit_settings_access_token_path(access_token)
    assert_response :success
  end

  test "#update should be implemented" do
    skip "TODO: Implement access token update"
  end

  test "requires authentication for destroy" do
    delete settings_access_token_path(access_token)
    assert_redirected_to new_session_path
  end

  test "deletes access token" do
    sign_in_as user
    access_token

    assert_difference("AccessToken.count", -1) do
      delete settings_access_token_path(access_token)
    end

    assert_redirected_to settings_access_tokens_path
    assert_equal "Access token '#{access_token.name}' has been deleted.", flash[:notice]
  end

  test "cannot delete other user's token" do
    other_token = create(:access_token, user: create(:user))
    sign_in_as user

    assert_no_difference("AccessToken.count") do
      delete settings_access_token_path(other_token)
    end

    assert_response :not_found
  end
end
