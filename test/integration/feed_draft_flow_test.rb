require "test_helper"

# Saving an AI draft and adding credentials remain available while extraction is paused.
class FeedDraftFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include OpenaiModelsTestHelpers

  setup { clear_enqueued_jobs }

  def user
    @user ||= regular_user
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def ai_url
    "https://no-rss-example.com/blog"
  end

  test "full flow: save AI credentials and keep the feed as a draft while extraction is unavailable" do
    sign_in_as(user)
    access_token

    assert_difference("Feed.count", 1) do
      post feeds_path, params: {
        feed: {
          params: { prompt: ai_url },
          name: "No-RSS Blog",
          feed_profile_key: "llm"
        },
        commit: "save_as_draft_and_add_credentials"
      }
    end

    draft = Feed.last
    assert_predicate draft, :draft?
    assert_equal user.id, draft.user_id
    assert_equal "llm", draft.feed_profile_key
    assert_equal ai_url, draft.source_input
    assert_nil draft.ai_credential_id
    assert_nil draft.search_credential_id
    assert_redirected_to new_ai_credential_path(feed_id: draft.id)

    follow_redirect!
    assert_response :success

    assert_difference("AiCredential.count", 1) do
      post ai_credentials_path, params: {
        feed_id: draft.id,
        ai_credential: {
          provider: "openai",
          display_name: "My OpenAI key",
          credential_data: { api_key: "sk-ant-#{SecureRandom.hex(16)}" }
        }
      }
    end

    ai_credential = AiCredential.last
    draft.reload
    assert_equal ai_credential.id, draft.ai_credential_id
    assert_redirected_to ai_credential_path(ai_credential, feed_id: draft.id)

    stub_openai_models(key: ai_credential.credential_data["api_key"])
    AiCredentialValidationJob.perform_now(ai_credential.latest_operation_run(:validation))

    assert_predicate ai_credential.reload, :active?
    assert_predicate ai_credential.latest_operation_run(:validation), :succeeded?
    assert_nil ai_credential.active_operation_run(:validation)
    follow_redirect!
    assert_response :success
    assert_includes response.body, "future-openai-model"

    patch feed_path(draft), params: {
      feed: { name: "Renamed AI draft", params: { prompt: "follow a different blog" },
              access_token_id: access_token.id, target_group: "testgroup" },
      enable_feed: "1"
    }

    assert_response :unprocessable_entity
    assert_predicate draft.reload, :draft?
    assert_equal "Renamed AI draft", draft.name
    assert_equal "follow a different blog", draft.source_input
    assert_equal ai_credential.id, draft.ai_credential_id
    assert_includes response.body, Loader::LlmLoader::UNAVAILABLE_MESSAGE
    assert_not_requested :post, /./
  end
end
