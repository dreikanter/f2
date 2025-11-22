require "test_helper"

class Settings::AccessTokensControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user)
  end

  test "#index should require authentication" do
    get settings_access_tokens_path
    assert_redirected_to new_session_path
  end

  test "#index should show access tokens list" do
    sign_in_as user
    get settings_access_tokens_path

    assert_response :success
    assert_select "h1", "Access Tokens"
  end

  test "#index should display empty state" do
    sign_in_as user
    get settings_access_tokens_path

    assert_response :success
    assert_select "h2", "No access tokens yet"
  end

  test "#index should display existing tokens" do
    sign_in_as user
    access_token
    get settings_access_tokens_path

    assert_response :success
    assert_select "[data-key='settings.access_tokens.#{access_token.id}']"
  end

  test "#show should redirect to sign in form" do
    get settings_access_token_path(access_token)
    assert_redirected_to new_session_path
  end

  test "#show should render for own token" do
    sign_in_as user
    get settings_access_token_path(access_token)

    assert_response :success
    assert_select "h1", access_token.name
  end

  test "#show should not render for other user's token" do
    other_token = create(:access_token, user: create(:user))
    sign_in_as user
    get settings_access_token_path(other_token)

    assert_response :not_found
  end

  test "#new should render when authenticated" do
    sign_in_as user
    get new_settings_access_token_path

    assert_response :success
  end

  test "#create should redirect to show page on success" do
    sign_in_as user

    assert_difference("AccessToken.count", 1) do
      post settings_access_tokens_path, params: {
        access_token: {
          name: "Test Token",
          token: "test_token_123",
          host: AccessToken::FREEFEED_HOSTS[:production][:url]
        }
      }
    end

    assert_redirected_to settings_access_token_path(AccessToken.last)
  end


  test "#create should render new form on validation error" do
    sign_in_as user

    assert_no_difference("AccessToken.count") do
      post settings_access_tokens_path, params: {
        access_token: {
          name: "Test Token",
          token: "", # Invalid: empty token
          host: AccessToken::FREEFEED_HOSTS[:production][:url]
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "h1", "New Access Token"
  end

  test "#create should reject unknown host" do
    sign_in_as user

    assert_no_difference("AccessToken.count") do
      post settings_access_tokens_path, params: {
        access_token: {
          name: "Test Token",
          token: "test_token_123",
          host: "https://unknown.example.com"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "h1", "New Access Token"
  end

  test "#create should require authentication" do
    assert_no_difference("AccessToken.count") do
      post settings_access_tokens_path, params: {
        access_token: {
          name: "Test Token",
          token: "test_token_123",
          host: AccessToken::FREEFEED_HOSTS[:production][:url]
        }
      }
    end

    assert_redirected_to new_session_path
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
