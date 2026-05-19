require "test_helper"

class LlmCredentials::DefaultsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  test "#update should set the credential as default and un-default siblings" do
    sign_in_as(user)
    first = create(:llm_credential, :default, user: user, provider: "anthropic", display_name: "first")
    second = create(:llm_credential, user: user, provider: "anthropic", display_name: "second")

    patch llm_credential_default_url(second)

    assert_redirected_to llm_credentials_path
    assert second.reload.is_default?
    refute first.reload.is_default?
  end

  test "#update should set default when no other default exists" do
    sign_in_as(user)
    credential = create(:llm_credential, user: user, provider: "anthropic")

    patch llm_credential_default_url(credential)

    assert credential.reload.is_default?
  end

  test "#update should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:llm_credential, user: other_user, provider: "anthropic")

    patch llm_credential_default_url(other)

    assert_response :not_found
    refute other.reload.is_default?
  end

  test "#update should require authentication" do
    credential = create(:llm_credential, user: user)
    patch llm_credential_default_url(credential)
    assert_redirected_to new_session_path
  end
end
