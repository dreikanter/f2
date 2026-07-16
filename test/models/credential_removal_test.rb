require "test_helper"

class CredentialRemovalTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  test "destroying an AI credential detaches every feed, disables enabled feeds, and records per-feed events" do
    credential = create(:ai_credential, user: user)
    draft_feed = create(:feed, :draft, user: user, ai_credential: credential)
    disabled_feed = create(:feed, :disabled, user: user, ai_credential: credential)
    enabled_feed = create(:feed, :disabled, user: user, ai_credential: credential)
    enabled_feed.update_columns(state: Feed.states[:enabled])

    assert_difference("Event.count", 3) do
      credential.destroy!
    end

    assert_nil draft_feed.reload.ai_credential_id
    assert_predicate draft_feed, :draft?
    assert_nil disabled_feed.reload.ai_credential_id
    assert_predicate disabled_feed, :disabled?
    assert_nil enabled_feed.reload.ai_credential_id
    assert_predicate enabled_feed, :disabled?

    assert_removal_event(draft_feed, AiCredential::REMOVED_EVENT_TYPE, disabled: false)
    assert_removal_event(disabled_feed, AiCredential::REMOVED_EVENT_TYPE, disabled: false)
    assert_removal_event(enabled_feed, AiCredential::REMOVED_EVENT_TYPE, disabled: true)
  end

  test "destroying a search credential detaches every feed, disables enabled feeds, and records per-feed events" do
    credential = create(:search_credential, user: user)
    draft_feed = create(:feed, :draft, user: user, search_credential: credential)
    disabled_feed = create(:feed, :disabled, user: user, search_credential: credential)
    enabled_feed = create(:feed, :disabled, user: user, search_credential: credential)
    enabled_feed.update_columns(state: Feed.states[:enabled])

    assert_difference("Event.count", 3) do
      credential.destroy!
    end

    assert_nil draft_feed.reload.search_credential_id
    assert_predicate draft_feed, :draft?
    assert_nil disabled_feed.reload.search_credential_id
    assert_predicate disabled_feed, :disabled?
    assert_nil enabled_feed.reload.search_credential_id
    assert_predicate enabled_feed, :disabled?

    assert_removal_event(draft_feed, SearchCredential::REMOVED_EVENT_TYPE, disabled: false)
    assert_removal_event(disabled_feed, SearchCredential::REMOVED_EVENT_TYPE, disabled: false)
    assert_removal_event(enabled_feed, SearchCredential::REMOVED_EVENT_TYPE, disabled: true)
  end

  private

  def assert_removal_event(feed, type, disabled:)
    event = feed.events.find_by!(type: type)

    assert_equal "warning", event.level
    assert_equal user, event.user
    assert_equal disabled, event.metadata["disabled"]
  end
end
