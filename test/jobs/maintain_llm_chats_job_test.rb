require "test_helper"

class MaintainLlmChatsJobTest < ActiveJob::TestCase
  test "#perform should interrupt overdue work and leave settled and current chats alone" do
    overdue = create(:llm_chat, deadline_at: 1.second.ago)
    current = create(:llm_chat)
    settled = create(:llm_chat)
    settled.finish!(status: :failed, error_category: "provider_error")

    MaintainLlmChatsJob.perform_now

    assert overdue.reload.interrupted?
    assert_equal "deadline_exceeded", overdue.error_category
    assert overdue.finished_at
    assert current.reload.running?
    assert_nil current.finished_at
    assert settled.reload.failed?
    assert_equal "provider_error", settled.error_category
  end

  test "#perform should purge transcript records while preserving accounting and other event references" do
    expired = create(:llm_chat, created_at: 7.days.ago)
    current = create(:llm_chat)
    message = expired.messages.create!(role: "assistant")
    result = expired.messages.create!(role: "tool", content: "Source")
    tool_call = message.ruby_llm_tool_calls.create!(tool_call_id: "purged_call", name: "lookup", result: result)
    sdk_usage = expired.ruby_llm_usages.create!(message: message, operation: "chat", provider: "openai", model: "gpt-5-nano", status: "succeeded")
    usage = create(:llm_usage, user: expired.user)
    event = create(:event, user: expired.user, type: "web_search")
    event.event_references.create!(reference: expired)
    accounting_reference = event.event_references.create!(reference: usage)

    MaintainLlmChatsJob.perform_now

    assert_not LlmChat.exists?(expired.id)
    assert_not expired.finish!(status: :succeeded)
    assert_not LlmMessage.exists?(message.id)
    assert_not LlmMessage.exists?(result.id)
    assert_not RubyLLM::ActiveRecord::ToolCall.exists?(tool_call.id)
    assert_not RubyLLM::ActiveRecord::Usage.exists?(sdk_usage.id)
    assert RubyLLM::ActiveRecord::Model.exists?(expired.ruby_llm_model_id)
    assert LlmChat.exists?(current.id)
    assert LlmUsage.exists?(usage.id)
    assert_equal [accounting_reference], event.reload.event_references.to_a
  end
end
