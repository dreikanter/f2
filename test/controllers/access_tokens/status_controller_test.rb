require "test_helper"

class AccessTokens::StatusControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user)
  end

  test "requires authentication" do
    post access_token_status_path(access_token)
    assert_redirected_to new_session_path
  end

  test "creates validation job for user's token" do
    sign_in_as user

    assert_enqueued_with(job: TokenValidationJob, args: [access_token]) do
      post access_token_status_path(access_token),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
  end

  test "responds with turbo stream" do
    sign_in_as user

    post access_token_status_path(access_token),
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.content_type, "text/vnd.turbo-stream.html"
    assert_includes response.body, "turbo-stream"
  end

  test "cannot validate other user's token" do
    other_user = create(:user)
    other_token = create(:access_token, user: other_user)

    sign_in_as user

    post access_token_status_path(other_token)
    assert_response :not_found
  end

  test "show responds with turbo stream" do
    sign_in_as user

    get access_token_status_path(access_token),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.content_type, "text/vnd.turbo-stream.html"
    assert_includes response.body, "turbo-stream"
  end
end
