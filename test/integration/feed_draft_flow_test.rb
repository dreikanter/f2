require "test_helper"

# End-to-end integration test covering the headline user flow of the
# feed-drafts feature (User Stories 1 and 2):
#
#   1. Start a feed pointing at an AI-requiring URL with no LLM credentials.
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
# (the controller flow is the focus, not the LlmCredentialValidationJob).
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
    # user picked an AI profile but has no LLM credentials, so the gate kicks
    # in and routes the request to credential setup with the freshly-saved
    # draft pre-attached.
    assert_difference("Feed.count", 1) do
      post feeds_path, params: {
        feed: {
          url: ai_url,
          name: "No-RSS Blog",
          feed_profile_key: "llm_website_extractor"
        },
        commit: "save_as_draft_and_add_credentials"
      }
    end

    draft = Feed.last
    assert_predicate draft, :draft?, "Feed should be saved as a draft"
    assert_equal user.id, draft.user_id
    assert_equal "llm_website_extractor", draft.feed_profile_key
    assert_equal ai_url, draft.url
    assert_equal "No-RSS Blog", draft.name
    assert_nil draft.llm_credential_id, "No credential yet at draft-save time"
    assert_redirected_to new_llm_credential_path(feed_id: draft.id)

    # Step 3: follow the redirect and submit the credential form. The
    # controller should create the credential, auto-attach it to the draft,
    # and redirect to the credential show page carrying feed_id.
    follow_redirect!
    assert_response :success

    assert_difference("LlmCredential.count", 1) do
      post llm_credentials_path, params: {
        feed_id: draft.id,
        llm_credential: {
          provider: "anthropic",
          display_name: "My Anthropic key",
          credential_data: { api_key: "sk-ant-#{SecureRandom.hex(16)}" }
        }
      }
    end

    credential = LlmCredential.last
    assert_equal user.id, credential.user_id
    assert_equal "pending", credential.state
    draft.reload
    assert_equal credential.id, draft.llm_credential_id, "Credential should be auto-attached to the draft"
    assert_redirected_to llm_credential_path(credential, feed_id: draft.id)

    # Step 4: stub the validation job by flipping the credential state
    # directly. Re-fetch the show page and confirm the "Continue setting up
    # your feed" call-to-action is rendered with a link back to the feed
    # editor.
    credential.update!(state: :active, last_validated_at: Time.current)

    get llm_credential_path(credential, feed_id: draft.id)
    assert_response :success
    assert_select "[data-key='llm_credential.return-to']" do
      assert_select "[href=?]", edit_feed_path(draft), text: /Continue setting up your feed/
    end

    # Step 5: visit the edit page, fill in the remaining required fields,
    # tick "Enable feed", and submit with a fresh preview_token. The feed
    # should transition into the enabled state.
    get edit_feed_path(draft)
    assert_response :success

    preview_token = PreviewToken.sign(
      user_id: user.id,
      profile_key: "llm_website_extractor",
      params: { "url" => ai_url },
      generated_at: Time.current
    )

    patch feed_path(draft), params: {
      feed: {
        access_token_id: access_token.id,
        target_group: "testgroup",
        schedule_interval: "1h",
        llm_credential_id: credential.id
      },
      enable_feed: "1",
      preview_token: preview_token
    }

    assert_redirected_to feed_path(draft)
    draft.reload
    assert_equal "enabled", draft.state
    assert_equal "No-RSS Blog", draft.name

    # Source-side fields stay anchored once the feed leaves the draft envelope:
    # strong params silently drops url, feed_profile_key, and params on
    # non-drafts (FR-026/027/028). Keep enable_feed=1 so the operational save
    # leaves the feed in the enabled state.
    patch feed_path(draft), params: {
      feed: {
        url: "https://attacker.example/feed.xml",
        feed_profile_key: "rss"
      },
      enable_feed: "1"
    }
    draft.reload
    assert_equal "enabled", draft.state, "Feed should stay enabled across the operational-only edit"
    assert_equal ai_url, draft.url, "Source URL should be locked after promotion"
    assert_equal "llm_website_extractor", draft.feed_profile_key, "Profile key should be locked after promotion"

    # Step 6: feeds index should show the feed in the enabled bucket of the
    # 3-bucket summary line, and the row itself should not carry the Draft
    # badge or draft-only inline actions anymore.
    get feeds_path
    assert_response :success
    assert_select "p", text: /1 active feed/
    assert_select "[data-key=?]", "feed.#{draft.id}.draft_badge", false
    assert_select "[data-key=?]", "feed.#{draft.id}.continue_setup", false
    assert_select "a[href=?]", feed_path(draft), text: "No-RSS Blog"
  end
end
