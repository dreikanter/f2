require "test_helper"

class LlmCredentials::ValidationsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def credential
    @credential ||= create(:llm_credential, user: user, state: :pending)
  end

  test "#show should require authentication" do
    get llm_credential_validation_url(credential)
    assert_redirected_to new_session_path
  end

  test "#show should render the validation polling turbo stream for own credential" do
    sign_in_as(user)

    get llm_credential_validation_url(credential),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
    assert_includes response.body, "llm-credential-show"
  end

  test "#show should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:llm_credential, user: other_user)

    get llm_credential_validation_url(other),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :not_found
  end

  test "#show should render the partial with feed_id when feed_id is provided" do
    sign_in_as(user)
    active = create(:llm_credential, :active, user: user)
    draft = create(:feed, :draft, user: user)

    get llm_credential_validation_url(active, feed_id: draft.id),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "llm-credential-show"
    assert_includes response.body, edit_feed_path(draft.id)
  end
end
