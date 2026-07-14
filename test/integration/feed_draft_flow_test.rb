require "test_helper"

# End-to-end integration test for saving an AI feed as a draft, adding each
# required credential type, and enabling the completed feed.
class FeedDraftFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def ai_url
    "https://no-rss-example.com/blog"
  end

  test "full flow: add AI and search credentials, then enable the draft" do
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
          provider: "anthropic",
          display_name: "My Anthropic key",
          credential_data: { api_key: "sk-ant-#{SecureRandom.hex(16)}" }
        }
      }
    end

    ai_credential = AiCredential.last
    draft.reload
    assert_equal ai_credential.id, draft.ai_credential_id
    assert_redirected_to ai_credential_path(ai_credential, feed_id: draft.id)

    ai_credential.update!(
      state: :active,
      last_validated_at: Time.current,
      available_models: [{ "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" }]
    )

    get edit_feed_path(draft)
    assert_response :success
    assert_select "button[value='save_as_draft_and_add_credentials']", count: 0
    assert_select "button[value='save_as_draft_and_add_search_credentials']"

    patch feed_path(draft), params: {
      feed: {
        access_token_id: access_token.id,
        target_group: "testgroup",
        schedule_interval: "1h",
        ai_credential_id: ai_credential.id,
        ai_model: "claude-sonnet-4-6"
      },
      commit: "save_as_draft_and_add_search_credentials"
    }

    assert_redirected_to new_search_credential_path(feed_id: draft.id)
    follow_redirect!
    assert_response :success

    assert_difference("SearchCredential.count", 1) do
      post search_credentials_path, params: {
        feed_id: draft.id,
        search_credential: {
          provider: "serper",
          display_name: "My Serper key",
          credential_data: { api_key: "serper-#{SecureRandom.hex(16)}" }
        }
      }
    end

    search_credential = SearchCredential.last
    draft.reload
    assert_equal search_credential.id, draft.search_credential_id
    assert_redirected_to search_credential_path(search_credential, feed_id: draft.id)

    search_credential.update!(state: :active, last_validated_at: Time.current)

    get search_credential_path(search_credential, feed_id: draft.id)
    assert_response :success
    assert_select "[data-key='search_credential.return-to']" do
      assert_select "[href=?]", edit_feed_path(draft), text: /Continue setting up your feed/
    end

    patch feed_path(draft), params: {
      feed: {
        access_token_id: access_token.id,
        target_group: "testgroup",
        schedule_interval: "1h",
        ai_credential_id: ai_credential.id,
        search_credential_id: search_credential.id,
        ai_model: "claude-sonnet-4-6"
      },
      enable_feed: "1"
    }

    assert_redirected_to feed_path(draft)
    draft.reload
    assert_equal "enabled", draft.state
    assert_equal "No-RSS Blog", draft.name

    patch feed_path(draft), params: {
      feed: {
        params: { prompt: "follow a different blog" },
        feed_profile_key: "rss"
      },
      enable_feed: "1"
    }
    draft.reload
    assert_equal "enabled", draft.state
    assert_equal "follow a different blog", draft.source_input
    assert_equal "llm", draft.feed_profile_key

    get feeds_path
    assert_response :success
    assert_select "p", text: /1 active feed/
    assert_select "[data-key=?] svg[aria-label=?]", "feed.#{draft.id}.status_icon", "Enabled"
    assert_select "[data-key=?]", "feed.#{draft.id}.continue_setup", false
    assert_select "a[href=?]", feed_path(draft), text: "No-RSS Blog"
  end
end
