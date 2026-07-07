require "test_helper"

# End-to-end integration test covering the headline user flow of the
# feed-drafts feature (User Stories 1 and 2):
#
#   1. Start a feed pointing at an AI-requiring URL with no AI credentials.
#   2. Submit via the credential-gate commit -> feed persists as draft, user is
#      sent to credential creation with feed_id pre-attached.
#   3. Submit the credential form -> credential is created, auto-attached to
#      the draft, user is redirected to the credential show page with feed_id.
#   4. Once the credential validates as active, the show page surfaces a
#      "Continue setting up your feed" affordance pointing at the feed editor.
#   5. From the editor, tick "Enable feed" and submit -> draft promotes to
#      enabled state with source-side fields now anchored.
#   6. Feeds index shows the feed in the enabled bucket of the summary line.
#
# Validation of the credential is stubbed by toggling the state directly
# (the controller flow is the focus, not the AiCredentialValidationJob).
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

  test "full flow: save draft via credential gate, create credential, enable feed, see it in index" do
    sign_in_as(user)
    access_token # ensure user has a usable access token for enabling later

    # Step 1+2: submit the new-feed form via the credential gate commit. The
    # user picked an AI profile but has no AI credentials, so the gate kicks
    # in and routes the request to credential setup with the freshly-saved
    # draft pre-attached.
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
    assert_predicate draft, :draft?, "Feed should be saved as a draft"
    assert_equal user.id, draft.user_id
    assert_equal "llm", draft.feed_profile_key
    assert_equal ai_url, draft.source_input
    assert_equal "No-RSS Blog", draft.name
    assert_nil draft.ai_credential_id, "No credential yet at draft-save time"
    assert_redirected_to new_ai_credential_path(feed_id: draft.id)

    # Step 3: follow the redirect and submit the credential form. The
    # controller should create the credential, auto-attach it to the draft,
    # and redirect to the credential show page carrying feed_id.
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

    credential = AiCredential.last
    assert_equal user.id, credential.user_id
    assert_equal "pending", credential.state
    draft.reload
    assert_equal credential.id, draft.ai_credential_id, "Credential should be auto-attached to the draft"
    assert_redirected_to ai_credential_path(credential, feed_id: draft.id)

    # Step 4: stub the validation job by flipping the credential state
    # directly. Re-fetch the show page and confirm the "Continue setting up
    # your feed" call-to-action is rendered with a link back to the feed
    # editor.
    credential.update!(state: :active, last_validated_at: Time.current,
                       available_models: [{ "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" }])

    get ai_credential_path(credential, feed_id: draft.id)
    assert_response :success
    assert_select "[data-key='ai_credential.return-to']" do
      assert_select "[href=?]", edit_feed_path(draft), text: /Continue setting up your feed/
    end

    # Step 5: visit the edit page, fill in the remaining required fields,
    # tick "Enable feed", and submit. Previewing is optional — the feed should
    # transition to the enabled state without requiring a recent preview.
    get edit_feed_path(draft)
    assert_response :success

    patch feed_path(draft), params: {
      feed: {
        access_token_id: access_token.id,
        target_group: "testgroup",
        schedule_interval: "1h",
        ai_credential_id: credential.id,
        ai_model: "claude-sonnet-4-6"
      },
      enable_feed: "1"
    }

    assert_redirected_to feed_path(draft)
    draft.reload
    assert_equal "enabled", draft.state
    assert_equal "No-RSS Blog", draft.name

    # The engine stays anchored once the feed leaves the draft envelope — a
    # forged feed_profile_key is dropped — but an AI feed's prompt is its source
    # and stays editable on a live feed (spec §4). Keep enable_feed=1 so the save
    # leaves the feed enabled.
    patch feed_path(draft), params: {
      feed: {
        params: { prompt: "follow a different blog" },
        feed_profile_key: "rss"
      },
      enable_feed: "1"
    }
    draft.reload
    assert_equal "enabled", draft.state, "Feed should stay enabled across the edit"
    assert_equal "follow a different blog", draft.source_input, "AI prompt stays editable on a live feed"
    assert_equal "llm", draft.feed_profile_key, "Engine stays locked — feed_profile_key can't be mass-assigned"

    # Step 6: feeds index should show the feed in the enabled bucket of the
    # 3-bucket summary line, and the row itself should carry the enabled
    # status icon rather than draft-only inline actions.
    get feeds_path
    assert_response :success
    assert_select "p", text: /1 active feed/
    assert_select "[data-key=?] svg[aria-label=?]", "feed.#{draft.id}.status_icon", "Enabled"
    assert_select "[data-key=?]", "feed.#{draft.id}.continue_setup", false
    assert_select "a[href=?]", feed_path(draft), text: "No-RSS Blog"
  end
end
