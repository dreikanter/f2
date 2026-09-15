require "test_helper"

class LlmNativeExecutionTest < ActiveSupport::TestCase
  class Lookup < RubyLLM::Tool
    description "Return a fixture source"
    parameter :query, type: :string

    def execute(query:)
      { url: "https://example.com/source", title: query }
    end
  end

  test "#call should send bounded requests and preserve native SDK usage" do
    record = staged_chat
    record.with_server_tools(:web_search)
    record.with_schema(type: "object", properties: { items: { type: "array", items: { type: "string" } } }, required: ["items"], additionalProperties: false)
    request = stub_request(:post, "https://api.openai.com/v1/responses").with do |http|
      payload = JSON.parse(http.body)
      assert_equal "Bearer test-execution-key", http.headers["Authorization"]
      assert_equal "gpt-5-nano", payload.fetch("model")
      assert_equal 16_384, payload.fetch("max_output_tokens")
      assert_equal 4, payload.fetch("max_tool_calls")
      assert_equal "web_search", payload.fetch("tools").sole.fetch("type")
      assert_equal true, payload.dig("text", "format", "strict")
      true
    end.to_return_json(body: completed_response)

    response = execution(record).call

    assert_equal '{"items":[]}', response.content
    usage = record.ruby_llm_usages.sole
    assert_equal "succeeded", usage.status
    assert_equal 40, usage.input_tokens
    assert_equal 20, usage.output_tokens
    assert usage.total_cost.positive?
    assert_equal record.messages.last, usage.message
    assert_requested request, times: 1
  end

  test "#call should stop before a fifth physical request without creating accounting rows" do
    record = staged_chat
    record.with_tools(Lookup)
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return { { body: tool_response.to_json, headers: { "Content-Type" => "application/json" } } }

    assert_no_difference "LlmUsage.count" do
      assert_raises(LlmNativeExecution::RequestLimitExceeded) { execution(record).call }
    end

    assert_equal 4, record.ruby_llm_usages.count
    assert_requested request, times: 4
  end

  test "#call should accept a final answer on the fourth request" do
    record = staged_chat
    record.with_tools(Lookup)
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return_json(body: tool_response)
      .then.to_return_json(body: tool_response)
      .then.to_return_json(body: tool_response)
      .then.to_return_json(body: completed_response)

    assert_equal '{"items":[]}', execution(record).call.content

    assert_equal 4, record.ruby_llm_usages.count
    assert_requested request, times: 4
  end

  test "#call should reduce the hosted tool budget across requests" do
    record = staged_chat
    record.with_tools(Lookup).with_server_tools(:web_search)
    payloads = []
    first_response = tool_response
    first_response[:output].unshift(completed_response.fetch("output").first)
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .with { |http| payloads << JSON.parse(http.body) }
      .to_return_json(body: first_response).then.to_return_json(body: completed_response)

    execution(record).call

    assert_equal [4, 3], payloads.map { |payload| payload.fetch("max_tool_calls") }
    assert_equal 2, record.ruby_llm_usages.count
    assert_requested request, times: 2
  end

  test "#call should stop when hosted tools consume the remaining budget" do
    record = staged_chat
    record.with_tools(Lookup).with_server_tools(:web_search)
    response = tool_response
    response[:output].concat(4.times.map { |index| { type: "web_search_call", id: "search_#{index}", status: "completed" } })
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)

    assert_raises(LlmNativeExecution::ToolLimitExceeded) { execution(record).call }

    assert_equal 1, record.ruby_llm_usages.count
    assert_requested request, times: 1
  end

  test "#call should preserve a provider failure without retrying or falling back" do
    record = staged_chat
    record.with_fallbacks("gpt-4.1")
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return_json(status: 500, body: { error: { message: "Provider unavailable", type: "server_error" } })

    assert_raises(RubyLLM::ServerError) { execution(record).call }

    assert_equal "failed", record.ruby_llm_usages.sole.status
    assert_requested request, times: 1
  end

  test "#call should reject an expired deadline without a provider request" do
    record = staged_chat(deadline_at: Time.current)

    assert_raises(LlmNativeExecution::DeadlineExceeded) { execution(record).call }

    assert_empty record.ruby_llm_usages
    assert_not_requested :post, "https://api.openai.com/v1/responses"
  end

  test "#call should reject a response received at the 180 second deadline" do
    record = staged_chat
    runner = execution(record)
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do
      travel_to record.started_at + 180.seconds, with_usec: true
      { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
    end

    assert_raises(LlmNativeExecution::DeadlineExceeded) { runner.call }

    assert_equal 1, record.ruby_llm_usages.count
    assert_requested request, times: 1
  end

  test "#call should interrupt a blocked request at the earlier preview deadline" do
    record = staged_chat(purpose: :preview, deadline_at: 1.second.from_now)
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do
      sleep 5
      { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
    end
    runner = execution(record)

    assert_raises(LlmNativeExecution::DeadlineExceeded) { runner.call }

    assert_requested request, times: 1
  end

  private

  def staged_chat(**attributes)
    record = create(:llm_chat, **attributes)
    record.context = provider.context
    record.protocol = :responses
    record.ask_later("Find one item.")
    record
  end

  def provider
    LlmProvider::Openai.new(credential_data: { "api_key" => "test-execution-key" })
  end

  def execution(record)
    LlmNativeExecution.new(chat: record, provider: provider)
  end

  def completed_response
    JSON.parse(file_fixture("llm_transcripts/completed.json").read)
  end

  def tool_response
    {
      id: "response_tool", model: "gpt-5-nano", status: "completed",
      output: [{ type: "function_call", call_id: "call_#{SecureRandom.hex(4)}", name: Lookup.tool_name, arguments: '{"query":"News"}' }],
      usage: { input_tokens: 20, output_tokens: 10 }
    }
  end
end
