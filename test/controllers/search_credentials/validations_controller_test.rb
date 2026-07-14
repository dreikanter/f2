require "test_helper"

class SearchCredentials::ValidationsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def credential
    @credential ||= create(:search_credential, user: user, state: :pending)
  end

  test "#show should require authentication" do
    get search_credential_validation_url(credential)

    assert_redirected_to new_session_path
  end

  test "#show should return no content while still pending" do
    sign_in_as(user)

    get search_credential_validation_url(credential),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :no_content
    assert_empty response.body
  end

  test "#show should return no content while still validating" do
    sign_in_as(user)
    validating = create(:search_credential, user: user, state: :validating)

    get search_credential_validation_url(validating),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :no_content
    assert_empty response.body
  end

  test "#show should render the turbo stream once validation resolves" do
    sign_in_as(user)
    active = create(:search_credential, :active, user: user)

    get search_credential_validation_url(active),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
    assert_includes response.body, "search-credential-show"
    assert_includes response.body, "search_credential.active"
  end

  test "#show should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:search_credential, user: other_user)

    get search_credential_validation_url(other),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :not_found
  end
end
