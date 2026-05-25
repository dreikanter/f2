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
    assert_select "[data-key='empty-state']", text: /No AI credentials yet/
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

  test "#new should accept and remember a feed_id owned by current_user" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user)

    get new_llm_credential_url, params: { feed_id: draft.id }

    assert_response :success
    assert_select "[data-key='llm_credentials.new']"
    assert_select "a[href=?]", edit_feed_path(draft.id), text: "Back to your feed"
  end

  test "#new should ignore foreign feed_id" do
    sign_in_as(user)
    other_draft = create(:feed, :draft, user: other_user)

    get new_llm_credential_url, params: { feed_id: other_draft.id }

    assert_response :success
    assert_select "[data-key='llm_credentials.new']"
  end

  test "#create should auto-attach the credential to the owned feed" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user)

    post llm_credentials_url, params: {
      feed_id: draft.id,
      llm_credential: {
        provider: "anthropic",
        display_name: "My Key",
        credential_data: { api_key: "sk-ant-#{SecureRandom.hex(16)}" }
      }
    }

    saved = LlmCredential.last
    draft.reload
    assert_equal saved.id, draft.llm_credential_id
  end

  test "#create should not attach when feed_id is foreign" do
    sign_in_as(user)
    other_draft = create(:feed, :draft, user: other_user)
    original_credential_id = other_draft.llm_credential_id

    post llm_credentials_url, params: {
      feed_id: other_draft.id,
      llm_credential: {
        provider: "anthropic",
        display_name: "My Key",
        credential_data: { api_key: "sk-ant-#{SecureRandom.hex(16)}" }
      }
    }

    other_draft.reload
    assert_equal original_credential_id, other_draft.llm_credential_id
  end

  test "#create should redirect with feed_id in the show path" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user)

    post llm_credentials_url, params: {
      feed_id: draft.id,
      llm_credential: {
        provider: "anthropic",
        display_name: "My Key",
        credential_data: { api_key: "sk-ant-#{SecureRandom.hex(16)}" }
      }
    }

    saved = LlmCredential.last
    assert_redirected_to llm_credential_path(saved, feed_id: draft.id)
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

  test "#show should render Continue setting up your feed link when credential is active and feed_id is owned" do
    sign_in_as(user)
    active = create(:llm_credential, :active, user: user)
    draft = create(:feed, :draft, user: user)

    get llm_credential_url(active, feed_id: draft.id)

    assert_response :success
    assert_select "a[href=?]", edit_feed_path(draft.id), text: "Continue setting up your feed"
  end

  test "#show should not render Continue setting up your feed link when credential is pending" do
    sign_in_as(user)
    pending = create(:llm_credential, user: user, state: :pending)
    draft = create(:feed, :draft, user: user)

    get llm_credential_url(pending, feed_id: draft.id)

    assert_response :success
    assert_select "a", text: "Continue setting up your feed", count: 0
  end

  test "#show should render a back-to-feed link when credential is inactive and feed_id is owned" do
    sign_in_as(user)
    inactive = create(:llm_credential, :inactive, user: user)
    draft = create(:feed, :draft, user: user)

    get llm_credential_url(inactive, feed_id: draft.id)

    assert_response :success
    assert_select "a[href=?]", edit_feed_path(draft.id), text: "Back to your feed"
  end

  test "#show should not render Continue setting up your feed link when feed_id is missing" do
    sign_in_as(user)
    active = create(:llm_credential, :active, user: user)

    get llm_credential_url(active)

    assert_response :success
    assert_select "a", text: "Continue setting up your feed", count: 0
  end

  test "#destroy should delete own credential" do
    sign_in_as(user)
    credential

    assert_difference("LlmCredential.count", -1) do
      delete llm_credential_url(credential)
    end
    assert_redirected_to llm_credentials_path
  end

  test "#destroy should keep usage rows and clear their credential reference" do
    sign_in_as(user)
    usage = create(:llm_usage, user: user, llm_credential: credential)

    assert_difference("LlmCredential.count", -1) do
      assert_no_difference("LlmUsage.count") do
        delete llm_credential_url(credential)
      end
    end
    assert_redirected_to llm_credentials_path
    assert_nil usage.reload.llm_credential_id
  end

  test "#destroy should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:llm_credential, user: other_user)
    delete llm_credential_url(other)
    assert_response :not_found
  end
end
