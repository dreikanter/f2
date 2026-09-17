require "test_helper"

class SmartFeedCreationAiWebsiteTest < ActionDispatch::IntegrationTest
  include CacheTestHelpers
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= regular_user
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def credential
    @credential ||= create(:ai_credential, :active, user: user)
  end

  def search_credential
    @search_credential ||= create(:search_credential, :active, user: user)
  end

  def ai_url
    "https://no-rss-example.com/blog"
  end

  test "#post should preserve AI selections when saving a draft" do
    create(:llm_model, model_id: "gpt-4.1")
    sign_in_as(user)
    access_token
    credential
    search_credential

    assert_no_difference ["LlmChat.count", "RubyLLM::ActiveRecord::Usage.count"] do
      post feeds_path, params: {
        feed: { params: { prompt: ai_url }, name: "Saved AI feed", feed_profile_key: "llm",
                access_token_id: access_token.id, target_group: "testgroup", schedule_interval: "1h",
                ai_credential_id: credential.id, ai_model: "gpt-4.1",
                search_credential_id: search_credential.id },
        enable_feed: "0"
      }
    end

    assert_response :redirect
    assert_predicate Feed.last, :draft?
    assert_equal credential.id, Feed.last.ai_credential_id
    assert_equal "gpt-4.1", Feed.last.ai_model
    assert_equal search_credential.id, Feed.last.search_credential_id
    assert_not_requested :any, /./
  end

  test "#show should gate on credentials when an AI profile has no usable credential" do
    sign_in_as(user)

    with_memory_cache do
      post feed_previews_path, params: { profile_key: "llm", "params" => { "prompt" => ai_url } }

      assert_response :success
      assert_select "[data-key='credentials.gate']"
      assert_no_enqueued_jobs
    end
  end

  test "#post should accept save-anyway after a preview failure and land as draft" do
    sign_in_as(user)
    access_token
    credential

    assert_difference("Feed.count", 1) do
      post feeds_path, params: {
        feed: {
          params: { prompt: ai_url },
          name: "No-RSS Blog",
          feed_profile_key: "llm",
          access_token_id: access_token.id,
          target_group: "testgroup",
          schedule_interval: "1h",
          ai_credential_id: credential.id
        },
        enable_feed: "0"
      }
    end

    assert_equal "draft", Feed.last.state
  end
end
