require "test_helper"

class LlmExecutionTest < ActiveSupport::TestCase
  class Lookup < RubyLLM::Tool
    description "Return a fixture source"
    parameter :query, type: :string

    def execute(query:)
      { url: "https://example.com/source", title: query }
    end
  end

  class AdvanceClock < RubyLLM::Tool
    description "Advance the test clock during a tool call"

    def initialize(clock)
      @clock = clock
    end

    def execute
      @clock.travel 180.seconds
      "Finished after the deadline"
    end
  end

  test "#call should send bounded requests and preserve RubyLLM usage" do
    record = staged_chat
    record.with_server_tools(:web_search)
    record.with_provider_options(service_tier: "default", max_tool_calls: 99, max_output_tokens: 100_000)
    payload = nil
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do |http|
      payload = JSON.parse(http.body)
      { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
    end

    runner = execution(record)
    response = runner.call

    assert_equal '{"items":[]}', response.content
    assert_same response, runner.call
    assert_equal 16_384, payload.fetch("max_output_tokens")
    assert_equal 16, payload.fetch("max_tool_calls")
    assert_equal "default", payload.fetch("service_tier")
    usage = record.ruby_llm_usages.sole
    assert_equal "succeeded", usage.status
    assert_equal 40, usage.input_tokens
    assert_equal 20, usage.output_tokens
    assert usage.total_cost.positive?
    assert_equal record.messages.last, usage.message
    assert_requested request, times: 1
  end

  test "#call should enforce limits when provider options have string keys" do
    record = staged_chat
    record.with_provider_options("max_output_tokens" => 100_000, "max_tool_calls" => 99, "service_tier" => "default")
    payload = nil
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do |http|
      payload = JSON.parse(http.body)
      { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
    end

    execution(record).call

    assert_equal 16_384, payload.fetch("max_output_tokens")
    assert_equal 16, payload.fetch("max_tool_calls")
    assert_equal "default", payload.fetch("service_tier")
    assert_requested request, times: 1
  end

  { "model ceiling" => [8_192, 4_096], "prepared limit" => [1_024, 1_024] }.each do |limit_name, (prepared_limit, expected_limit)|
    test "#call should respect the lower #{limit_name}" do
      chat = provider.context.chat(model: "gpt-4-turbo", provider: :openai, protocol: provider.protocol)
      chat.with_max_output_tokens(prepared_limit)
      chat.with_provider_options(max_output_tokens: 100_000)
      chat.ask_later("Find one item.")
      payload = nil
      request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do |http|
        payload = JSON.parse(http.body)
        response = completed_response.merge("model" => "gpt-4-turbo")
        { body: response.to_json, headers: { "Content-Type" => "application/json" } }
      end

      LlmExecution.new(chat: chat, provider: provider, deadline_at: 180.seconds.from_now).call

      assert_equal expected_limit, payload.fetch("max_output_tokens")
      assert_equal expected_limit, chat.max_output_tokens
      assert_equal "gpt-4-turbo", payload.fetch("model")
      assert_requested request, times: 1
    end
  end

  test "#call should run a prepared SDK chat without resolving or replacing its selected model" do
    chat = provider.context.chat(model: "custom-model", provider: :openai, protocol: provider.protocol, assume_model_exists: true)
    chat.ask_later("Find one item.")
    context = chat.context
    payload = nil
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .with(headers: { "Authorization" => "Bearer test-execution-key" })
      .to_return do |http|
        payload = JSON.parse(http.body)
        response = completed_response.merge("model" => "custom-model")
        { body: response.to_json, headers: { "Content-Type" => "application/json" } }
      end

    LlmExecution.new(chat: chat, provider: provider, deadline_at: 180.seconds.from_now).call

    assert_equal "custom-model", payload.fetch("model")
    assert_equal 16_384, payload.fetch("max_output_tokens")
    assert_equal "custom-model", chat.model.id
    assert_same context, chat.context
    assert_requested request, times: 1
  end

  test "#initialize should reject SDK retries that could exceed the physical request budget" do
    context = RubyLLM.context do |config|
      config.openai_api_key = "test-execution-key"
      config.max_retries = 3
    end
    chat = context.chat(model: "gpt-5-nano", provider: :openai, protocol: provider.protocol)
    chat.ask_later("Find one item.")

    assert_raises(ArgumentError) do
      LlmExecution.new(chat: chat, provider: provider, deadline_at: 180.seconds.from_now)
    end

    assert_not_requested :post, "https://api.openai.com/v1/responses"
  end

  test "#call should stop before a fifth physical request" do
    record = staged_chat
    record.with_tools(Lookup)
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return { { body: tool_response.to_json, headers: { "Content-Type" => "application/json" } } }

    assert_raises(LlmExecution::RequestLimitExceeded) { execution(record).call }

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
      .to_return do |http|
        payloads << JSON.parse(http.body)
        response = payloads.size == 1 ? first_response : completed_response
        { body: response.to_json, headers: { "Content-Type" => "application/json" } }
      end

    execution(record).call

    assert_equal [16, 15], payloads.map { |payload| payload.fetch("max_tool_calls") }
    assert_equal 2, record.ruby_llm_usages.count
    assert_requested request, times: 2
  end

  test "#call should stop when hosted tools consume the remaining budget" do
    record = staged_chat
    record.with_tools(Lookup).with_server_tools(:web_search)
    response = tool_response
    response[:output].concat(16.times.map { |index| { type: "web_search_call", id: "search_#{index}", status: "completed" } })
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)

    assert_raises(LlmExecution::ToolLimitExceeded) { execution(record).call }

    assert_equal 1, record.ruby_llm_usages.count
    assert_requested request, times: 1
  end

  test "#call should accept a final answer at the hosted tool limit" do
    record = staged_chat
    record.with_server_tools(:web_search)
    response = completed_response
    response["output"] = Array.new(16) do |index|
      { type: "web_search_call", id: "search_#{index}", status: "completed" }
    end + response["output"].select { |item| item["type"] == "message" }
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)

    assert_equal '{"items":[]}', execution(record).call.content

    assert_equal 1, record.ruby_llm_usages.count
    assert_requested request, times: 1
  end

  test "#call should recognize provider tool exhaustion even below the local limit" do
    record = staged_chat
    record.with_server_tools(:web_search)
    response = completed_response
    response["status"] = "incomplete"
    response["incomplete_details"] = { "reason" => "max_tool_calls" }
    response["output"].reject! { |item| item["type"] == "message" }
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)

    assert_raises(LlmExecution::ToolLimitExceeded) { execution(record).call }

    assert_equal 1, record.ruby_llm_usages.count
    assert_requested request, times: 1
  end

  test "#call should reject a tool-exhausted response with partial text" do
    record = staged_chat
    record.with_server_tools(:web_search)
    response = completed_response
    response["status"] = "incomplete"
    response["incomplete_details"] = { "reason" => "max_tool_calls" }
    message = response["output"].last
    message["content"].first["text"] = '{"items":['
    response["output"] = Array.new(16) do |index|
      { type: "web_search_call", id: "search_#{index}", status: "completed" }
    end + [message]
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)

    assert_raises(LlmExecution::ToolLimitExceeded) { execution(record).call }

    assert_equal '{"items":[', record.messages.last.content
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

    assert_raises(LlmExecution::DeadlineExceeded) { execution(record).call }

    assert_empty record.ruby_llm_usages
    assert_not_requested :post, "https://api.openai.com/v1/responses"
  end

  test "#call should reject a response received at the 180 second deadline" do
    freeze_time do
      record = staged_chat
      runner = execution(record)
      request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do
        travel 180.seconds
        { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
      end

      assert_raises(LlmExecution::DeadlineExceeded) { runner.call }

      assert_equal 1, record.ruby_llm_usages.count
      assert_requested request, times: 1
    end
  end

  test "#initialize should reject concurrent local tools before making requests" do
    record = staged_chat
    record.with_tools(Lookup)
    record.with_tool_options(concurrency: :threads)

    assert_raises(ArgumentError) { execution(record) }

    assert_not_requested :post, "https://api.openai.com/v1/responses"
  end

  test "#call should stop between local tools when the first finishes after the deadline" do
    freeze_time do
      record = staged_chat
      record.with_tools(AdvanceClock.new(self), Lookup)
      response = tool_response
      response[:output].unshift(type: "function_call", call_id: "slow_call", name: AdvanceClock.tool_name, arguments: "{}")
      request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)

      assert_raises(LlmExecution::DeadlineExceeded) { execution(record).call }

      assert_equal ["Finished after the deadline"], record.messages.where(role: "tool").pluck(:content)
      assert_requested request, times: 1
    end
  end

  test "#call should reject a late response at the earlier preview deadline" do
    freeze_time do
      record = staged_chat(purpose: :preview, deadline_at: 10.seconds.from_now)
      request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do
        travel 10.seconds
        { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
      end
      runner = execution(record)

      assert_raises(LlmExecution::DeadlineExceeded) { runner.call }

      assert_equal 1, record.ruby_llm_usages.count
      assert_requested request, times: 1
    end
  end

  private

  def staged_chat(**attributes)
    record = create(:llm_chat, **attributes)
    record.context = provider.context
    record.protocol = provider.protocol
    record.ask_later("Find one item.")
    record
  end

  def provider
    LlmProvider::Openai.new(credential_data: { "api_key" => "test-execution-key" })
  end

  def execution(record)
    LlmExecution.new(chat: record.to_llm, provider: provider, deadline_at: record.deadline_at)
  end

  def completed_response
    JSON.parse(file_fixture("llm_transcripts/completed.json").read)
  end

  def tool_response
    {
      id: "response_tool",
      model: "gpt-5-nano",
      status: "completed",
      output: [{ type: "function_call", call_id: "call_#{SecureRandom.hex(4)}", name: Lookup.tool_name, arguments: '{"query":"News"}' }],
      usage: { input_tokens: 20, output_tokens: 10 }
    }
  end
end
