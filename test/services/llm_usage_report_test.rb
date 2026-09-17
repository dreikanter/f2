require "test_helper"

class LlmUsageReportTest < ActiveSupport::TestCase
  test "#totals should count each SDK attempt once despite repeated references and shared messages" do
    feed = create(:feed)
    chat = create(:llm_chat, user: feed.user, feed: feed)
    message = chat.messages.create!(role: "assistant")
    event = create(:event, user: feed.user, subject: feed, type: "feed_refresh")
    event.event_references.create!(reference: chat)
    other_event = create(:event, user: feed.user, subject: feed, type: "feed_refresh")
    other_event.event_references.create!(reference: chat)
    create(:ruby_llm_usage, chat: chat, message: message, total_cost: "0.004",
                            input_tokens: 10, output_tokens: 3, cache_read_tokens: 2, thinking_tokens: 1)
    create(:ruby_llm_usage, chat: chat, message: message, status: "failed", total_cost: "0.004",
                            input_tokens: 20, output_tokens: 4, cache_write_tokens: 5, thinking_tokens: 2)
    create(:ruby_llm_usage, chat: create(:llm_chat, user: feed.user, feed: feed), total_cost: 9)

    totals = LlmUsageReport.for_event(event).totals

    assert_equal 2, totals.call_count
    assert_equal totals, LlmUsageReport.new(chats: feed.llm_chats.joins(:event_references)).totals
    assert_equal BigDecimal("0.008"), totals.total_cost
    assert_equal 30, totals.input_tokens
    assert_equal 7, totals.output_tokens
    assert_equal 2, totals.cache_read_tokens
    assert_equal 5, totals.cache_write_tokens
    assert_equal 3, totals.thinking_tokens
    assert_equal({ llm_calls: 2, llm_cost_cents: 0.8 }, totals.event_stats)
  end

  test "#totals should preserve known spend and mark mixed costs incomplete" do
    feed = create(:feed)
    chat = create(:llm_chat, user: feed.user, feed: feed)
    create(:ruby_llm_usage, chat: chat, total_cost: "0.03")
    create(:ruby_llm_usage, chat: chat, total_cost: nil, status: "failed")
    create(:ruby_llm_usage, chat: chat, total_cost: 0)

    totals = LlmUsageReport.for_feed(feed).totals

    assert_equal 3, totals.call_count
    assert_equal BigDecimal("0.03"), totals.known_cost
    assert_equal 1, totals.unknown_cost_count
    assert totals.incomplete?
    assert_nil totals.total_cost
    assert_nil totals.event_stats.fetch(:llm_cost_cents)
  end

  test "#totals should distinguish unknown costs from free calls and empty reports" do
    feed = create(:feed)
    empty = LlmUsageReport.for_feed(feed).totals
    assert_equal 0, empty.call_count
    assert_equal 0, empty.total_cost
    assert_not empty.incomplete?
    assert_empty empty.event_stats

    chat = create(:llm_chat, user: feed.user, feed: feed)
    create(:ruby_llm_usage, chat: chat, total_cost: 0)
    free = LlmUsageReport.for_feed(feed).totals
    assert_equal 0, free.total_cost
    assert_not free.incomplete?

    create(:ruby_llm_usage, chat: chat, total_cost: nil)
    unknown = LlmUsageReport.for_feed(feed).totals
    assert_equal 0, unknown.known_cost
    assert unknown.incomplete?
    assert_nil unknown.total_cost
  end

  test ".for_credential should include previews and refreshes across feeds without crossing credentials" do
    credential = create(:ai_credential, :active)
    first_feed = create(:feed, user: credential.user, ai_credential: credential)
    second_feed = create(:feed, user: credential.user, ai_credential: credential)
    refresh = create(:llm_chat, user: credential.user, feed: first_feed, ai_credential: credential)
    saved_preview = create(:llm_chat, user: credential.user, feed: second_feed,
                                      ai_credential: credential, purpose: :preview)
    unsaved_preview = create(:llm_chat, user: credential.user, ai_credential: credential, purpose: :preview)
    other_credential = create(:ai_credential, :active, user: credential.user, display_name: "Other")
    other_chat = create(:llm_chat, user: credential.user, feed: first_feed, ai_credential: other_credential)
    create(:ruby_llm_usage, chat: refresh, total_cost: "0.01")
    create(:ruby_llm_usage, chat: saved_preview, total_cost: "0.02")
    create(:ruby_llm_usage, chat: unsaved_preview, total_cost: "0.03")
    create(:ruby_llm_usage, chat: other_chat, total_cost: "0.04")
    create(:ruby_llm_usage, total_cost: 99)

    totals = LlmUsageReport.for_credential(credential).totals

    assert_equal 3, totals.call_count
    assert_equal BigDecimal("0.06"), totals.total_cost
    assert_equal BigDecimal("0.05"), LlmUsageReport.for_feed(first_feed).totals.total_cost
    assert_equal BigDecimal("0.02"), LlmUsageReport.for_feed(second_feed).totals.total_cost
  end

  test "#totals_for_periods should use usage timestamps and include exact rolling boundaries" do
    freeze_time do
      feed = create(:feed)
      chat = create(:llm_chat, user: feed.user, feed: feed, created_at: 40.days.ago)
      create(:ruby_llm_usage, chat: chat, created_at: Time.current, total_cost: "0.01")
      create(:ruby_llm_usage, chat: chat, created_at: 1.day.ago, total_cost: "0.02")
      create(:ruby_llm_usage, chat: chat, created_at: 1.week.ago, total_cost: "0.03")
      create(:ruby_llm_usage, chat: chat, created_at: 30.days.ago, total_cost: nil)
      create(:ruby_llm_usage, chat: chat, created_at: 30.days.ago - 1.second, total_cost: 9)
      create(:ruby_llm_usage, chat: chat, created_at: 1.second.from_now, total_cost: 9)

      totals = LlmUsageReport.for_feed(feed).totals_for_periods

      assert_equal 2, totals[:day].call_count
      assert_equal BigDecimal("0.03"), totals[:day].total_cost
      assert_equal 3, totals[:week].call_count
      assert_equal BigDecimal("0.06"), totals[:week].total_cost
      assert_equal 4, totals[:month].call_count
      assert totals[:month].incomplete?
      assert_nil totals[:month].total_cost
      assert_equal 1, LlmUsageReport.for_feed(feed, period: 1.day.ago...Time.current).totals.call_count
    end
  end

  test "#totals should report only retained SDK data after interruption and pruning" do
    feed = create(:feed)
    interrupted = create(:llm_chat, user: feed.user, feed: feed, deadline_at: 1.second.ago)
    expired = create(:llm_chat, user: feed.user, feed: feed, created_at: LlmChat::RETENTION.ago)
    current = create(:llm_chat, user: feed.user, feed: feed)
    event = create(:event, user: feed.user, subject: feed, type: "feed_refresh")
    event.event_references.create!(reference: expired)
    create(:ruby_llm_usage, chat: expired, total_cost: "0.02")
    create(:ruby_llm_usage, chat: current, total_cost: "0.03")
    assert_equal 2, LlmUsageReport.for_feed(feed).totals.call_count

    MaintainLlmChatsJob.perform_now

    assert interrupted.reload.interrupted?
    assert_empty interrupted.ruby_llm_usages
    assert_equal 1, LlmUsageReport.for_feed(feed).totals.call_count
    assert_equal BigDecimal("0.03"), LlmUsageReport.for_feed(feed).totals.total_cost
    assert_empty LlmUsageReport.for_event(event).usages
    assert_empty LlmUsageReport.for_event(event).totals.event_stats
  end
end
