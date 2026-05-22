require "test_helper"

class LlmCredentialsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def credential
    @credential ||= create(:llm_credential, user: user)
  end

  test "#index should require authentication" do
    get llm_credentials_url
    assert_redirected_to new_session_path
  end

  test "#index should render the user's credentials" do
    sign_in_as(user)
    credential
    create(:llm_credential, user: other_user) # not visible

    get llm_credentials_url

    assert_response :success
    assert_select "[data-key='llm_credentials.index']"
    assert_select "[data-key='llm_credential.#{credential.id}']"
  end

  test "#index should show the empty state when the user has no credentials" do
    sign_in_as(user)
    get llm_credentials_url
    assert_response :success
    assert_select "h2", text: /No AI credentials yet/
  end

  test "#new should render the form" do
    sign_in_as(user)
    get new_llm_credential_url
    assert_response :success
    assert_select "[data-key='llm_credentials.new']"
    assert_select "[data-key='llm_credentials.provider']"
    assert_select "[data-key='llm_credentials.credential-data.api_key']"
  end

  test "#create should save and enqueue validation when params are valid" do
    sign_in_as(user)

    assert_difference("LlmCredential.count", 1) do
      assert_enqueued_with(job: LlmCredentialValidationJob) do
        post llm_credentials_url, params: {
          llm_credential: {
            provider: "anthropic",
            display_name: "My Key",
            credential_data: { api_key: "sk-ant-#{SecureRandom.hex(16)}" }
          }
        }
      end
    end

    saved = LlmCredential.last
    assert_redirected_to llm_credential_path(saved)
    assert_equal "pending", saved.state
  end

  test "#create should preserve return_to through to the show redirect" do
    sign_in_as(user)
    return_to = "/feed_identifications?input=https%3A%2F%2Fexample.com"

    post llm_credentials_url, params: {
      return_to: return_to,
      llm_credential: {
        provider: "anthropic",
        display_name: "My Key",
        credential_data: { api_key: "sk-ant-#{SecureRandom.hex(16)}" }
      }
    }

    saved = LlmCredential.last
    assert_redirected_to llm_credential_path(saved, return_to: return_to)
  end

  test "#new should embed return_to in the form action" do
    sign_in_as(user)
    return_to = "/feed_identifications?input=https%3A%2F%2Fexample.com"

    get new_llm_credential_url, params: { return_to: return_to }

    assert_response :success
    assert_select "form[action=?]", llm_credentials_path(return_to: return_to)
  end

  test "#show should carry return_to into the validation polling endpoint" do
    sign_in_as(user)
    pending = create(:llm_credential, user: user, state: :pending)
    return_to = "/feed_identifications?input=https%3A%2F%2Fexample.com"

    get llm_credential_url(pending, return_to: return_to)

    assert_response :success
    assert_select "[data-polling-endpoint-value=?]",
                  llm_credential_validation_path(pending, return_to: return_to)
  end

  test "#create should render :new with errors on invalid input" do
    sign_in_as(user)

    assert_no_difference("LlmCredential.count") do
      post llm_credentials_url, params: {
        llm_credential: {
          provider: "anthropic",
          display_name: "",
          credential_data: { api_key: "x" }
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "[data-key='llm_credentials.new']"
  end

  test "#show should render own credential" do
    sign_in_as(user)
    get llm_credential_url(credential)
    assert_response :success
    assert_select "[data-key='llm_credential.show']"
  end

  test "#show should render the polling shell for a pending credential" do
    sign_in_as(user)
    pending = create(:llm_credential, user: user, state: :pending)

    get llm_credential_url(pending)

    assert_response :success
    assert_select "[data-controller='polling']"
    assert_select "[data-key='llm_credential.validating']"
  end

  test "#show should render the active state without polling for an active credential" do
    sign_in_as(user)
    active = create(:llm_credential, :active, user: user)

    get llm_credential_url(active)

    assert_response :success
    assert_select "[data-controller='polling']", false
    assert_select "[data-key='llm_credential.active']"
  end

  test "#show should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:llm_credential, user: other_user)
    get llm_credential_url(other)
    assert_response :not_found
  end

  test "#destroy should delete own credential" do
    sign_in_as(user)
    credential

    assert_difference("LlmCredential.count", -1) do
      delete llm_credential_url(credential)
    end
    assert_redirected_to llm_credentials_path
  end

  test "#destroy should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:llm_credential, user: other_user)
    delete llm_credential_url(other)
    assert_response :not_found
  end
end
