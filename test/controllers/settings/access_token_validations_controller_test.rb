require "test_helper"

class Settings::AccessTokenValidationsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user)
  end

  test "#show should require authentication" do
    get settings_access_token_validation_path(access_token)
    assert_redirected_to new_session_path
  end

  test "#show should respond with turbo_stream format" do
    sign_in_as user
    get settings_access_token_validation_path(access_token)

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
  end

  test "#show should replace access-token-show div" do
    sign_in_as user
    get settings_access_token_validation_path(access_token)

    assert_response :success
    assert_match /turbo-stream.*action="replace".*target="access-token-show"/, response.body
  end

  test "#show should not render for other user's token" do
    other_token = create(:access_token, user: create(:user))
    sign_in_as user
    get settings_access_token_validation_path(other_token)

    assert_response :not_found
  end

  test "#show should show validating state" do
    access_token.update!(status: :validating)
    sign_in_as user
    get settings_access_token_validation_path(access_token)

    assert_response :success
    assert_match /Validating token/, response.body
  end

  test "#show should show active state with data-status attribute" do
    access_token.update!(status: :active)
    sign_in_as user
    get settings_access_token_validation_path(access_token)

    assert_response :success
    assert_match /data-status="active"/, response.body
    assert_match /Token is active and ready to use/, response.body
  end

  test "#show should show inactive state with data-status attribute" do
    access_token.update!(status: :inactive)
    sign_in_as user
    get settings_access_token_validation_path(access_token)

    assert_response :success
    assert_match /data-status="inactive"/, response.body
    assert_match /Token is inactive/, response.body
  end
end
