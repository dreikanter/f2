require "test_helper"

class LlmUsageDetailsTest < ActiveSupport::TestCase
  test "#web_search_count should count OpenAI searches separately from other hosted tools" do
    chat = create(:llm_chat)
    message = chat.messages.create!(role: "assistant", server_tool_calls: [
      { type: "web_search_call", id: "search_1" },
      { type: "code_interpreter_call", id: "code_1" },
      { type: "web_search_call", id: "search_2" }
    ])
    usage = create(:ruby_llm_usage, chat: chat, message: message, provider: "openai")

    assert_equal 2, LlmUsageDetails.new(usage).web_search_count
  end

  test "#web_search_count should return zero without a recorded message" do
    usage = create(:ruby_llm_usage, provider: "openai", message: nil)

    assert_equal 0, LlmUsageDetails.new(usage).web_search_count
  end

  test "#web_search_count should return zero when the message has no recorded tools" do
    chat = create(:llm_chat)
    message = chat.messages.create!(role: "assistant")
    usage = create(:ruby_llm_usage, chat: chat, message: message, provider: "openai")

    assert_equal 0, LlmUsageDetails.new(usage).web_search_count
  end

  test "#web_search_count should use the recorded provider and leave unsupported formats unknown" do
    chat = create(:llm_chat)
    message = chat.messages.create!(role: "assistant", server_tool_calls: [{ type: "web_search_call", id: "search_1" }])
    usage = create(:ruby_llm_usage, chat: chat, message: message, provider: "openrouter", model: "openai/gpt-5-nano")

    assert_nil LlmUsageDetails.new(usage).web_search_count
  end
end
