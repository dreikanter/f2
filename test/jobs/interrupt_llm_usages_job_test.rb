require "test_helper"

class InterruptLlmUsagesJobTest < ActiveJob::TestCase
  test "#perform should interrupt only overdue pending attempts without inventing measurements" do
    freeze_time do
      overdue = create(:llm_usage, :pending, deadline_at: Time.current)
      current = create(:llm_usage, :pending)
      settled = create(:llm_usage, deadline_at: 1.second.ago)

      InterruptLlmUsagesJob.perform_now

      assert overdue.reload.interrupted?
      assert_nil overdue.finished_at
      assert_nil overdue.duration_ms
      assert_nil overdue.input_tokens
      assert_nil overdue.output_tokens
      assert_nil overdue.cost_estimate_cents
      assert current.reload.pending?
      assert settled.reload.success?
      assert_equal 1, settled.cost_estimate_cents
    end
  end

  test "#perform should recover accounting after the transcript was purged" do
    chat, event, usage = travel_to 8.days.ago do
      chat = create(:llm_chat)
      event = create(:event, user: chat.user)
      event.event_references.create!(reference: chat)
      [chat, event, LlmUsage.start!(chat: chat, event: event)]
    end
    deadline = usage.deadline_at

    MaintainLlmChatsJob.perform_now

    assert_not LlmChat.exists?(chat.id)
    assert usage.reload.pending?
    assert_equal deadline, usage.deadline_at
    assert_equal [usage], event.reload.references

    InterruptLlmUsagesJob.perform_now
    assert usage.reload.interrupted?
    assert_nil usage.cost_estimate_cents

    assert usage.settle!(outcome: :success, cost_estimate_cents: "0.5")
    assert_not usage.settle!(outcome: :success, cost_estimate_cents: "0.5")
    assert_equal BigDecimal("0.5"), usage.reload.cost_estimate_cents
    assert_equal [usage], event.reload.references
  end
end
