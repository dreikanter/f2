require "test_helper"

class AccessTokens::ValidationsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user)
  end

  test "#show should require authentication" do
    get access_token_validation_path(access_token)
    assert_redirected_to new_session_path
  end

  test "#show should respond with turbo_stream format once validation resolves" do
    access_token.update!(status: :active)
    sign_in_as user
    get access_token_validation_path(access_token)

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
  end

  test "#show should update access-token-show div once validation resolves" do
    access_token.update!(status: :active)
    sign_in_as user
    get access_token_validation_path(access_token)

    assert_response :success
    assert_match /turbo-stream.*action="update".*target="access-token-show"/, response.body
  end

  test "#show should return no content while pending" do
    sign_in_as user
    get access_token_validation_path(access_token)

    assert_response :no_content
    assert_empty response.body
  end

  test "#show should not render for other user's token" do
    other_token = create(:access_token, user: create(:user))
    sign_in_as user
    get access_token_validation_path(other_token)

    assert_response :not_found
  end

  test "#show should return no content while validating" do
    access_token.update!(status: :validating)
    sign_in_as user
    get access_token_validation_path(access_token)

    assert_response :no_content
    assert_empty response.body
  end

  test "#show should show active state with data-status attribute" do
    access_token.update!(status: :active)
    sign_in_as user
    get access_token_validation_path(access_token)

    assert_response :success
    assert_match /data-status="active"/, response.body
    assert_match />Valid</, response.body
  end

  test "#show should render the Continue link with feed_id when feed_id is provided" do
    access_token.update!(status: :active)
    sign_in_as user
    draft = create(:feed, :draft, user: user)

    get access_token_validation_path(access_token, feed_id: draft.id)

    assert_response :success
    assert_includes response.body, "access-token-show"
    assert_includes response.body, edit_feed_path(draft.id)
  end

  test "#show should settle a validation whose run never reported back" do
    access_token.update!(status: :validating, validation_started_at: (AccessToken::VALIDATION_STALE_AFTER + 1.minute).ago)
    sign_in_as user

    get access_token_validation_path(access_token)

    assert_response :success
    assert_match /data-status="inactive"/, response.body
    assert access_token.reload.inactive?
  end

  test "#show should keep waiting on a validation that is still in flight" do
    access_token.update!(status: :validating, validation_started_at: 1.minute.ago)
    sign_in_as user

    get access_token_validation_path(access_token)

    assert_response :no_content
    assert access_token.reload.validating?
  end

  test "#show should show inactive state with data-status attribute" do
    access_token.update!(status: :inactive, scopes: AccessToken::TOKEN_SCOPES)
    sign_in_as user
    get access_token_validation_path(access_token)

    assert_response :success
    assert_match /data-status="inactive"/, response.body
    assert_match /couldn't confirm this token/, response.body
  end
end
