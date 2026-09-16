require "test_helper"
require "view_component/test_case"

class LlmUsageListItemComponentTest < ViewComponent::TestCase
  def usage
    @usage ||= create(:ruby_llm_usage, model: "claude-sonnet-4-6",
                                  input_tokens: 1_000, output_tokens: 500, total_cost: "0.03")
  end

  def render_usage(record = usage)
    render_inline(LlmUsageListItemComponent.new(usage: record))
  end

  test "#render should show the recorded model" do
    result = render_usage

    assert_equal "claude-sonnet-4-6", result.css("[data-key='events.llm_usage.model']").text
  end

  test "#render should summarize input and output tokens" do
    result = render_usage

    tokens = result.css("[data-key='events.llm_usage.tokens']").text
    assert_equal "1,000 in · 500 out", tokens
  end

  test "#render should append cached tokens only when the call reused cache" do
    cached = create(:ruby_llm_usage, input_tokens: 10, output_tokens: 5,
                                cache_read_tokens: 200, cache_write_tokens: 40)

    result = render_usage(cached)

    assert_equal "10 in · 5 out · 240 cached", result.css("[data-key='events.llm_usage.tokens']").text
  end

  test "#render should format the call cost as currency" do
    result = render_usage

    assert_equal "$0.03", result.css("[data-key='events.llm_usage.cost']").text
  end

  test "#render should badge a successful outcome" do
    result = render_usage

    assert_equal "Succeeded", result.css("[data-key='events.llm_usage.outcome']").text
  end

  test "#render should badge a failed outcome" do
    failed = create(:ruby_llm_usage, status: "failed")

    result = render_usage(failed)

    assert_equal "Failed", result.css("[data-key='events.llm_usage.outcome']").text
  end
  test "#render should label unknown cost explicitly" do
    usage = create(:ruby_llm_usage, total_cost: nil)
    result = render_inline(LlmUsageListItemComponent.new(usage: usage))
    assert_equal "Unknown", result.css('[data-key="events.llm_usage.cost"]').first.text
  end

  test "#render should label missing token counts without inventing zeros" do
    usage = create(:ruby_llm_usage, input_tokens: nil, output_tokens: nil)
    result = render_usage(usage)

    assert_equal "Unknown in · Unknown out", result.css('[data-key="events.llm_usage.tokens"]').text
  end

  test "#render should show recorded thinking tokens" do
    usage = create(:ruby_llm_usage, thinking_tokens: 120)
    result = render_usage(usage)

    assert_equal "1,000 in · 500 out · 120 thinking", result.css('[data-key="events.llm_usage.tokens"]').text
  end

  test "#render should retain native search details after credential deletion" do
    credential = create(:ai_credential, :active)
    chat = create(:llm_chat, user: credential.user, ai_credential: credential)
    message = chat.messages.create!(role: "assistant", server_tool_calls: [
      { type: "web_search_call", id: "search_1" },
      { type: "code_interpreter_call", id: "code_1" },
      { type: "web_search_call", id: "search_2" }
    ])
    usage = create(:ruby_llm_usage, chat: chat, message: message, provider: "openai")
    credential.destroy!

    result = render_usage(usage.reload)

    assert_nil chat.reload.ai_credential_id
    assert_equal "1,000 in · 500 out · 2 native web calls", result.css('[data-key="events.llm_usage.tokens"]').text
  end

  test "#render should not apply OpenAI interpretation to an unsupported provider" do
    chat = create(:llm_chat)
    message = chat.messages.create!(role: "assistant", server_tool_calls: [{ type: "web_search_call", id: "search_1" }])
    usage = create(:ruby_llm_usage, chat: chat, message: message, provider: "openrouter", model: "openai/gpt-5-nano")

    result = render_usage(usage)

    assert_equal "1,000 in · 500 out", result.css('[data-key="events.llm_usage.tokens"]').text
  end
end
