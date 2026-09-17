require "test_helper"
require_relative "../../db/migrate/20260917010000_discard_stored_llm_usages"

class DiscardStoredLlmUsagesTest < ActiveSupport::TestCase
  test "#change should discard old usage and its references while preserving current accounting" do
    feed = create(:feed)
    event = create(:event, user: feed.user, subject: feed, type: "feed_refresh",
                          metadata: { "stats" => { "llm_calls" => 1, "llm_cost_cents" => 2 } })
    old_usage = create(:llm_usage, user: feed.user, feed: feed)
    old_reference = create(:event_reference, event: event, reference: old_usage)
    create(:llm_usage, user: feed.user, cost_estimate_cents: nil)
    chat = create(:llm_chat, user: feed.user, feed: feed)
    message = chat.messages.create!(role: "assistant", content: "Retained response")
    usage = create(:ruby_llm_usage, chat: chat, message: message, total_cost: nil)
    chat_reference = create(:event_reference, event: event, reference: chat)
    credential = create(:search_credential, :active, user: feed.user)
    search_event = WebSearchUsage.record!(credential: credential, refresh_event: event)
    search = event.event_references.find_by!(reference: search_event)
    search_attributes = search.reference.attributes
    metadata = event.metadata
    usage_attributes = usage.attributes
    migration = DiscardStoredLlmUsages.new

    migration.migrate(:up)

    assert_empty LlmUsage.all
    assert_not EventReference.exists?(old_reference.id)
    assert_equal chat, chat_reference.reload.reference
    assert_equal "Retained response", message.reload.content
    assert_equal usage_attributes, usage.reload.attributes
    assert_equal search_attributes, search.reload.reference.attributes
    assert_equal metadata, event.reload.metadata
    assert_equal 1, LlmUsageReport.for_event(event).totals.call_count
    assert_nil LlmUsageReport.for_event(event).totals.total_cost

    migration.migrate(:down)

    assert LlmUsage.table_exists?
    assert_empty LlmUsage.all
    assert_equal usage_attributes, usage.reload.attributes

    migration.migrate(:up)

    assert_empty LlmUsage.all
    assert_equal search_attributes, search.reload.reference.attributes
  end
end
