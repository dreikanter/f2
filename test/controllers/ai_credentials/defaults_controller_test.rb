require "test_helper"

class AiCredentials::DefaultsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  test "#update should set the credential as the user's default" do
    sign_in_as(user)
    first = create(:ai_credential, :default, user: user, provider: "anthropic", display_name: "first")
    second = create(:ai_credential, user: user, provider: "anthropic", display_name: "second")

    patch ai_credential_default_url(second)

    assert_redirected_to ai_credentials_path
    assert_equal second.id, user.reload.default_ai_credential_id
  end

  test "#update should set default when no other default exists" do
    sign_in_as(user)
    credential = create(:ai_credential, user: user, provider: "anthropic")

    patch ai_credential_default_url(credential)

    assert_equal credential.id, user.reload.default_ai_credential_id
  end

  test "#update should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:ai_credential, user: other_user, provider: "anthropic")

    patch ai_credential_default_url(other)

    assert_response :not_found
    assert_nil other_user.reload.default_ai_credential_id
  end

  test "#update should respond with turbo stream when requested" do
    sign_in_as(user)
    credential = create(:ai_credential, user: user, provider: "anthropic")

    patch ai_credential_default_url(credential), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :ok
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_equal credential.id, user.reload.default_ai_credential_id
  end

  test "#update should require authentication" do
    credential = create(:ai_credential, user: user)
    patch ai_credential_default_url(credential)
    assert_redirected_to new_session_path
  end
end
