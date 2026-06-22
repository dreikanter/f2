require "test_helper"

class AiCredentialsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def credential
    @credential ||= create(:ai_credential, user: user)
  end

  test "#index should require authentication" do
    get ai_credentials_url
    assert_redirected_to new_session_path
  end

  test "#index should render the user's credentials" do
    sign_in_as(user)
    credential
    create(:ai_credential, user: other_user) # not visible

    get ai_credentials_url

    assert_response :success
    assert_select "[data-key='ai_credentials.index']"
    assert_select "[data-key='ai_credential.#{credential.id}']"
  end

  test "#index should show the empty state when the user has no credentials" do
    sign_in_as(user)
    get ai_credentials_url
    assert_response :success
    assert_select "[data-key='empty-state']", text: /No AI credentials yet/
  end

  test "#new should render the form" do
    sign_in_as(user)
    get new_ai_credential_url
    assert_response :success
    assert_select "[data-key='ai_credentials.new']"
    assert_select "[data-key='ai_credentials.provider']"
    assert_select "[data-key='ai_credentials.credential-data.api_key']"
  end

  test "#create should save and enqueue validation when params are valid" do
    sign_in_as(user)

    assert_difference("AiCredential.count", 1) do
      assert_enqueued_with(job: AiCredentialValidationJob) do
        post ai_credentials_url, params: {
          ai_credential: {
            provider: "anthropic",
            display_name: "My Key",
            credential_data: { api_key: "sk-ant-#{SecureRandom.hex(16)}" }
          }
        }
      end
    end

    saved = AiCredential.last
    assert_redirected_to ai_credential_path(saved)
    assert_equal "pending", saved.state
  end

  test "#new should accept and remember a feed_id owned by current_user" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user)

    get new_ai_credential_url, params: { feed_id: draft.id }

    assert_response :success
    assert_select "[data-key='ai_credentials.new']"
    assert_select "a[href=?]", edit_feed_path(draft.id), text: "Back to your feed"
  end

  test "#new should ignore foreign feed_id" do
    sign_in_as(user)
    other_draft = create(:feed, :draft, user: other_user)

    get new_ai_credential_url, params: { feed_id: other_draft.id }

    assert_response :success
    assert_select "[data-key='ai_credentials.new']"
  end

  test "#create should auto-attach the credential to the owned feed" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user)

    post ai_credentials_url, params: {
      feed_id: draft.id,
      ai_credential: {
        provider: "anthropic",
        display_name: "My Key",
        credential_data: { api_key: "sk-ant-#{SecureRandom.hex(16)}" }
      }
    }

    saved = AiCredential.last
    draft.reload
    assert_equal saved.id, draft.ai_credential_id
  end

  test "#create should not attach when feed_id is foreign" do
    sign_in_as(user)
    other_draft = create(:feed, :draft, user: other_user)
    original_credential_id = other_draft.ai_credential_id

    post ai_credentials_url, params: {
      feed_id: other_draft.id,
      ai_credential: {
        provider: "anthropic",
        display_name: "My Key",
        credential_data: { api_key: "sk-ant-#{SecureRandom.hex(16)}" }
      }
    }

    other_draft.reload
    assert_equal original_credential_id, other_draft.ai_credential_id
  end

  test "#create should redirect with feed_id in the show path" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user)

    post ai_credentials_url, params: {
      feed_id: draft.id,
      ai_credential: {
        provider: "anthropic",
        display_name: "My Key",
        credential_data: { api_key: "sk-ant-#{SecureRandom.hex(16)}" }
      }
    }

    saved = AiCredential.last
    assert_redirected_to ai_credential_path(saved, feed_id: draft.id)
  end

  test "#create should generate a name when display_name is blank" do
    sign_in_as(user)

    assert_difference("AiCredential.count", 1) do
      post ai_credentials_url, params: {
        ai_credential: {
          provider: "anthropic",
          display_name: "",
          credential_data: { api_key: "sk-ant-#{SecureRandom.hex(16)}" }
        }
      }
    end

    saved = AiCredential.last
    assert saved.display_name.start_with?("Anthropic ")
    assert_equal 3, saved.display_name.split.count
  end

  test "#create should render :new with errors on invalid input" do
    sign_in_as(user)

    assert_no_difference("AiCredential.count") do
      post ai_credentials_url, params: {
        ai_credential: {
          provider: "anthropic",
          display_name: "My Key",
          credential_data: { api_key: "" }
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "[data-key='ai_credentials.new']"
  end

  test "#show should render own credential" do
    sign_in_as(user)
    get ai_credential_url(credential)
    assert_response :success
    assert_select "[data-key='ai_credential.show']"
  end

  test "#show should place edit and delete actions in the header" do
    sign_in_as(user)
    get ai_credential_url(credential)

    assert_response :success
    assert_select "header [data-key='ai_credential.edit']"
    assert_select "header form[action=?]", ai_credential_path(credential) do
      assert_select "button", text: /Delete/
    end
  end

  test "#show should render the polling shell for a pending credential" do
    sign_in_as(user)
    pending = create(:ai_credential, user: user, state: :pending)

    get ai_credential_url(pending)

    assert_response :success
    assert_select "[data-controller='polling']"
    assert_select "[data-key='ai_credential.validating']"
  end

  test "#show should render the active state without polling for an active credential" do
    sign_in_as(user)
    active = create(:ai_credential, :active, user: user)

    get ai_credential_url(active)

    assert_response :success
    assert_select "[data-controller='polling']", false
    assert_select "[data-key='ai_credential.active']"
  end

  test "#show should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:ai_credential, user: other_user)
    get ai_credential_url(other)
    assert_response :not_found
  end

  test "#show should render Continue setting up your feed link when credential is active and feed_id is owned" do
    sign_in_as(user)
    active = create(:ai_credential, :active, user: user)
    draft = create(:feed, :draft, user: user)

    get ai_credential_url(active, feed_id: draft.id)

    assert_response :success
    assert_select "a[href=?]", edit_feed_path(draft.id), text: "Continue setting up your feed"
  end

  test "#show should not render Continue setting up your feed link when credential is pending" do
    sign_in_as(user)
    pending = create(:ai_credential, user: user, state: :pending)
    draft = create(:feed, :draft, user: user)

    get ai_credential_url(pending, feed_id: draft.id)

    assert_response :success
    assert_select "a", text: "Continue setting up your feed", count: 0
  end

  test "#show should render a back-to-feed link when credential is inactive and feed_id is owned" do
    sign_in_as(user)
    inactive = create(:ai_credential, :inactive, user: user)
    draft = create(:feed, :draft, user: user)

    get ai_credential_url(inactive, feed_id: draft.id)

    assert_response :success
    assert_select "a[href=?]", edit_feed_path(draft.id), text: "Back to your feed"
  end

  test "#show should not render Continue setting up your feed link when feed_id is missing" do
    sign_in_as(user)
    active = create(:ai_credential, :active, user: user)

    get ai_credential_url(active)

    assert_response :success
    assert_select "a", text: "Continue setting up your feed", count: 0
  end

  test "#edit should render the form" do
    sign_in_as(user)
    get edit_ai_credential_url(credential)
    assert_response :success
    assert_select "[data-key='ai_credentials.edit']"
    assert_select "[data-key='ai_credentials.display-name']"
    assert_select "[data-key='ai_credentials.credential-data.api_key']"
  end

  test "#edit should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:ai_credential, user: other_user)
    get edit_ai_credential_url(other)
    assert_response :not_found
  end

  test "#update should update display_name, reset to pending, and re-enqueue validation" do
    sign_in_as(user)
    active = create(:ai_credential, :active, user: user)

    assert_enqueued_with(job: AiCredentialValidationJob) do
      patch ai_credential_url(active), params: {
        ai_credential: {
          display_name: "Renamed Key",
          credential_data: { api_key: "" }
        }
      }
    end

    active.reload
    assert_redirected_to ai_credential_path(active)
    assert_equal "Renamed Key", active.display_name
    assert_equal "pending", active.state
  end

  test "#update should replace credential_data when a new api_key is provided" do
    sign_in_as(user)
    active = create(:ai_credential, :active, user: user)
    new_key = "sk-ant-#{SecureRandom.hex(16)}"

    patch ai_credential_url(active), params: {
      ai_credential: {
        display_name: active.display_name,
        credential_data: { api_key: new_key }
      }
    }

    active.reload
    assert_equal new_key, active.credential_data["api_key"]
  end

  test "#update should keep existing credential_data when api_key is blank" do
    sign_in_as(user)
    active = create(:ai_credential, :active, user: user)
    original_key = active.credential_data["api_key"]

    patch ai_credential_url(active), params: {
      ai_credential: {
        display_name: active.display_name,
        credential_data: { api_key: "" }
      }
    }

    active.reload
    assert_equal original_key, active.credential_data["api_key"]
  end

  test "#update should render :edit with errors on invalid input" do
    sign_in_as(user)
    get edit_ai_credential_url(credential)

    patch ai_credential_url(credential), params: {
      ai_credential: {
        display_name: "",
        credential_data: { api_key: "" }
      }
    }

    assert_response :unprocessable_entity
    assert_select "[data-key='ai_credentials.edit']"
  end

  test "#update should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:ai_credential, user: other_user)

    patch ai_credential_url(other), params: {
      ai_credential: {
        display_name: "Hacked",
        credential_data: { api_key: "" }
      }
    }

    assert_response :not_found
  end

  test "#destroy should delete own credential" do
    sign_in_as(user)
    credential

    assert_difference("AiCredential.count", -1) do
      delete ai_credential_url(credential)
    end
    assert_redirected_to ai_credentials_path
  end

  test "#destroy should keep usage rows and clear their credential reference" do
    sign_in_as(user)
    usage = create(:llm_usage, user: user, ai_credential: credential)

    assert_difference("AiCredential.count", -1) do
      assert_no_difference("LlmUsage.count") do
        delete ai_credential_url(credential)
      end
    end
    assert_redirected_to ai_credentials_path
    assert_nil usage.reload.ai_credential_id
  end

  test "#destroy should 404 for another user's credential" do
    sign_in_as(user)
    other = create(:ai_credential, user: other_user)
    delete ai_credential_url(other)
    assert_response :not_found
  end
end
