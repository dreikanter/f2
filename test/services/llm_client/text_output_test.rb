require "test_helper"

class LlmClient::TextOutputTest < ActiveSupport::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions"
  SCHEMA = {
    "type" => "object",
    "properties" => { "items" => { "type" => "array", "items" => { "type" => "string" } } },
    "required" => ["items"],
    "additionalProperties" => false
  }.freeze

  def credential
    @credential ||= create(:ai_credential, :active, provider: "openai",
                            credential_data: { "api_key" => "text-output-test" })
  end

  def client
    @client ||= LlmClient.new(credential)
  end

  def context
    @context ||= LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader,
                                           model: "new-unregistered-model", purpose: :preview).tap do |ctx|
      ctx.native_search_disabled = true
    end
  end

  def completion(content, input: 20, output: 10, tool_calls: nil)
    {
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        choices: [{ message: { role: "assistant", content: content, tool_calls: tool_calls }.compact }],
        usage: { prompt_tokens: input, completion_tokens: output }
      }.to_json
    }
  end

  def rejection(status: 400, code: "unsupported_parameter", param: "response_format", message: "Unsupported parameter")
    {
      status: status,
      headers: { "Content-Type" => "application/json" },
      body: { error: { type: "invalid_request_error", code: code, param: param, message: message } }.to_json
    }
  end

  def stub_completions(*responses)
    @requests = []
    stub_request(:post, ENDPOINT)
      .with(headers: { "Authorization" => "Bearer text-output-test" }) do |request|
        @requests << JSON.parse(request.body)
        true
      end.to_return(*responses)
  end

  def call(**options)
    client.call(context, prompt: "Return an empty list", output_schema: SCHEMA, **options)
  end

  test "#call should use an exact unknown model ID and locally validate text JSON without optional API features" do
    stub_completions(completion("```json\n{\"items\":[]}\n```"))

    result = call(native_schema: false, system: "Keep supplied facts")

    assert_equal({ "items" => [] }, result.payload)
    request = @requests.sole
    assert_equal "new-unregistered-model", request["model"]
    assert_equal 8_192, request["max_completion_tokens"]
    assert_nil request["tools"]
    assert_nil request["response_format"]
    assert_nil request["reasoning_effort"]
    assert_equal "developer", request["messages"][0]["role"]
    assert_includes request["messages"][0]["content"], "Keep supplied facts"
    assert_includes request["messages"][0]["content"], SCHEMA.to_json
    assert_equal "Return an empty list", request["messages"][1]["content"]
    assert_equal "success", LlmUsage.find(result.usage_id).outcome
  end

  test "#call should send text JSON requests through the other provider transports" do
    [
      ["anthropic", "new-anthropic-model", "https://api.anthropic.com/v1/messages"],
      ["moonshot", "new-kimi-model", "https://api.moonshot.ai/v1/chat/completions"],
      ["openrouter", "vendor/new-model", "https://openrouter.ai/api/v1/chat/completions"]
    ].each do |provider, model, endpoint|
      key = create(:ai_credential, :active, provider: provider,
                   available_models: [{ "id" => model, "metadata" => { "tool_call" => false } }])
      ctx = LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader, model: model)
      response = completion('{"items":[]}')
      if provider == "anthropic"
        response[:body] = { content: [{ type: "text", text: '{"items":[]}' }],
                            usage: { input_tokens: 20, output_tokens: 10 } }.to_json
      end
      requests = []
      stub_request(:post, endpoint).with do |request|
        requests << JSON.parse(request.body)
        true
      end.to_return(response)

      result = LlmClient.new(key).call(ctx, prompt: "Empty list", output_schema: SCHEMA, native_schema: false, web: true)

      assert_equal({ "items" => [] }, result.payload)
      request = requests.sole
      assert_equal model, request["model"]
      assert_nil request["tools"]
      assert_nil request["response_format"]
      assert_nil request["output_config"]
      assert_nil request["provider"]
      assert_equal 8_192, request["max_tokens"]
    end
  end

  test "#call should retry an explicit schema rejection once with text instructions and record both attempts" do
    stub_completions(rejection, completion('{"items":[]}'))

    assert_difference -> { LlmUsage.count }, 2 do
      assert_equal({ "items" => [] }, call.payload)
    end

    assert_equal 2, @requests.size
    assert_equal "json_schema", @requests[0].dig("response_format", "type")
    assert_nil @requests[1]["response_format"]
    assert_includes @requests[1]["messages"][0]["content"], SCHEMA.to_json
    assert_equal ["new-unregistered-model"], @requests.pluck("model").uniq
    assert_equal %w[provider_error success], LlmUsage.order(:created_at).pluck(:outcome)
    assert_predicate credential.reload, :active?
  end

  test "#call should correct a malformed response once without repeating web tools" do
    search = create(:search_credential, :active, user: credential.user)
    @context = LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader,
                                          model: "new-unregistered-model", search_credential: search)
    stub_completions(completion('{"items":["found fact"],}', input: 30),
                     completion('{"items":["found fact"]}', input: 40))

    result = call(web: true)

    assert_equal({ "items" => ["found fact"] }, result.payload)
    assert_equal 2, @requests.size
    assert @requests[0]["tools"].present?
    assert_nil @requests[1]["tools"]
    assert_nil @requests[1]["response_format"]
    assert_nil @requests[1]["reasoning_effort"]
    assert_includes @requests[1]["messages"][0]["content"], "No web tools are available"
    assert_includes @requests[1]["messages"][1]["content"], "found fact"
    assert_equal %w[schema_error success], LlmUsage.order(:created_at).pluck(:outcome)
    assert_equal 70, LlmUsage.sum(:input_tokens)
    assert_equal 20, LlmUsage.sum(:output_tokens)
  end

  test "#call should correct an empty object with either native or text JSON output" do
    [true, false].each do |native_schema|
      @context = nil
      stub_completions(completion("{}"), completion('{"items":[]}'))

      assert_difference -> { LlmUsage.count }, 2 do
        assert_equal({ "items" => [] }, call(native_schema: native_schema).payload)
      end

      assert_equal 2, @requests.size
      assert_nil @requests[1]["response_format"]
      assert_nil @requests[1]["tools"]
    end
  end

  test "#call should not spend a correction attempt on a missing or whitespace-only response" do
    [nil, "", " \n\t"].each do |content|
      @context = nil
      stub_completions(completion(content))

      assert_difference -> { LlmUsage.count }, 1 do
        assert_raises(LlmClient::SchemaError) { call }
      end

      assert_equal 1, @requests.size
    end
  end

  test "#call should stop when the correction still violates the local schema" do
    stub_completions(completion('{"items":[42]}'))

    assert_raises(LlmClient::SchemaError) { call(native_schema: false) }

    assert_equal 2, @requests.size
    assert_equal %w[schema_error schema_error], LlmUsage.order(:created_at).pluck(:outcome)
    assert_equal 40, LlmUsage.sum(:input_tokens)
  end

  test "#call should allow at most a schema fallback and one correction" do
    stub_completions(rejection, completion("not JSON"), completion("still not JSON"))

    assert_raises(LlmClient::SchemaError) { call }

    assert_equal 3, @requests.size
    assert_equal %w[provider_error schema_error schema_error], LlmUsage.order(:created_at).pluck(:outcome)
  end

  test "#call should keep a refusal out of the correction's feed items" do
    stub_completions(completion("I cannot browse the web."), completion('{"items":[]}'))

    assert_equal({ "items" => [] }, call.payload)
    assert_includes @requests[1]["messages"][0]["content"], "Refusals and capability limitations are"
    assert_includes @requests[1]["messages"][0]["content"], "not feed items"
  end

  test "#call should not retry malformed schemas or unrelated unsupported parameters" do
    [
      rejection(code: "invalid_json_schema", message: "Invalid schema: required is missing"),
      rejection(param: "tools"),
      rejection(param: "reasoning_effort"),
      rejection(code: nil, message: "Unsupported schema keyword: oneOf")
    ].each do |response|
      stub_completions(response)
      @context = nil

      assert_difference -> { LlmUsage.count }, 1 do
        assert_raises(LlmClient::ProviderError) { call }
      end
      assert_equal 1, @requests.size
    end
  end

  test "#call should not retry authentication rate limit server or context length errors" do
    [
      [rejection(status: 401), LlmClient::AuthError],
      [rejection(status: 429), LlmClient::RateLimited],
      [rejection(status: 500), LlmClient::ProviderError],
      [rejection(message: "Maximum context length exceeded"), LlmClient::ProviderError]
    ].each do |response, error_class|
      stub_completions(response)
      @context = nil

      assert_raises(error_class) { call }
      assert_equal 1, @requests.size
    end
  end

  test "#call should preserve billed tool rounds when a later request fails" do
    search = create(:search_credential, :active, user: credential.user)
    @context = LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader,
                                          model: "new-unregistered-model", search_credential: search)
    tool = { id: "fetch-1", type: "function",
             function: { name: LlmClient::Tools::WebFetch.new.name, arguments: { url: "ftp://example.com" }.to_json } }
    stub_completions(completion(nil, input: 51, output: 12, tool_calls: [tool]),
                     rejection(message: "Bad tool response", code: nil, param: "messages"))

    assert_raises(LlmClient::ProviderError) { call(web: true) }

    usage = LlmUsage.sole
    assert_equal 51, usage.input_tokens
    assert_equal 12, usage.output_tokens
    assert_equal "provider_error", usage.outcome
    assert_equal 2, @requests.size
    assert_equal 1, context.tool_budget.spent
  end

  test "#call should share its attempt allowance across gathering structuring and repairs" do
    stub_completions(completion("gathered"), rejection, completion("not JSON"), completion('{"items":[]}'))

    client.call(context, prompt: "Gather", output_schema: nil)
    assert_equal({ "items" => [] }, call.payload)
    assert_raises(LlmClient::Timeout) { call }

    assert_equal 4, @requests.size
  end

  test "#call should preserve the original deadline across calls on the same context" do
    stub_completions(completion('{"items":[]}'))
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    clock = ->(*) { now }

    Process.stub(:clock_gettime, clock) do
      call
      now += RubyLLM.config.request_timeout + 1
      assert_raises(LlmClient::Timeout) { call }
    end

    assert_equal 1, @requests.size
    assert_equal %w[success timeout], LlmUsage.order(:created_at).pluck(:outcome)
    assert_equal 0, LlmUsage.order(:created_at).last.input_tokens
  end
  test "#call should use advisory schema and output limits while validating output and tracking unknown spend" do
    credential.update!(available_models: [{ "id" => context.model,
      "metadata" => { "structured_output" => false, "max_output_tokens" => 1_024 } }])
    stub_completions(completion('{"items":[]}'))

    result = call

    assert_equal({ "items" => [] }, result.payload)
    assert_nil @requests.sole["response_format"]
    assert_equal 1_024, @requests.sole["max_completion_tokens"]
    assert_nil LlmUsage.find(result.usage_id).cost_estimate_cents
  end

  test "#call should offer web fetch without external search credentials" do
    stub_completions(completion('{"items":[]}'))

    assert_equal({ "items" => [] }, call(web: true).payload)

    assert_equal [LlmClient::Tools::WebFetch.new.name], @requests.sole["tools"].map { |tool| tool.dig("function", "name") }
    assert_includes @requests.sole["messages"][0]["content"], "Web search is unavailable"
  end

  test "#call should retry an explicit tool rejection without tools using supplied page evidence" do
    stub_request(:get, "https://example.com/post").to_return(body: "<p>A retrieved fact.</p>")
    stub_completions(rejection(param: "tools"), completion('{"items":["A retrieved fact."]}'))

    result = Socket.stub(:getaddrinfo, [["AF_INET", 0, "example.com", "93.184.216.34"]]) do
      client.call(context, prompt: "Summarize https://example.com/post", output_schema: SCHEMA, web: true)
    end

    assert_equal ["A retrieved fact."], result.payload["items"]
    assert @requests[0]["tools"].present?
    assert_nil @requests[1]["tools"]
    assert_nil @requests[1]["reasoning_effort"]
    assert_includes @requests[1]["messages"][1]["content"], "A retrieved fact."
    assert_includes @requests[1]["messages"][1]["content"], "https://example.com/post"
    assert_equal [context.model], @requests.pluck("model").uniq
    assert_equal %w[provider_error success], LlmUsage.order(:created_at).pluck(:outcome)
    assert_equal 1, context.tool_budget.spent
    assert_requested :get, "https://example.com/post", times: 1
  end

  test "#call should use supplied pages for a model with advisory tool support disabled" do
    credential.update!(available_models: [{ "id" => context.model, "metadata" => { "tool_call" => false } }])
    stub_request(:get, "https://example.com/post").to_return(body: "<p>A retrieved fact.</p>")
    stub_completions(rejection, completion('{"items":["A retrieved fact."]}'))

    result = Socket.stub(:getaddrinfo, [["AF_INET", 0, "example.com", "93.184.216.34"]]) do
      client.call(context, prompt: "Summarize https://example.com/post", output_schema: SCHEMA, web: true)
    end

    assert_equal ["A retrieved fact."], result.payload["items"]
    assert @requests.all? { |request| request["tools"].nil? }
    assert @requests.all? { |request| request["messages"][1]["content"].include?("A retrieved fact.") }
    assert_requested :get, "https://example.com/post", times: 1
    assert_equal 1, context.tool_budget.spent
  end

  test "#call should let the model respond with limited capabilities when no pages are supplied" do
    stub_completions(rejection(param: "tools"), completion('{"items":[]}'))

    assert_equal({ "items" => [] }, call(web: true).payload)
    assert_includes @requests[1]["messages"][0]["content"], "No web tools are available"
    assert_equal 0, context.tool_budget.spent
  end

  test "#call should not hide malformed tools or provider failures as missing capabilities" do
    [
      [rejection(param: "tools", code: "invalid_parameter", message: "Invalid function schema"), LlmClient::ProviderError],
      [rejection(param: "tools", status: 401), LlmClient::AuthError],
      [rejection(param: "tools", status: 429), LlmClient::RateLimited],
      [rejection(param: "tools", status: 500), LlmClient::ProviderError]
    ].each do |response, error_class|
      @context = nil
      stub_completions(response)

      assert_raises(error_class) { call(web: true) }
      assert_equal 1, @requests.size
    end
  end

  test "#call should not retry a repeated tool rejection once tools have been removed" do
    stub_completions(rejection(param: "tools"))

    assert_raises(LlmClient::ProviderError) { call(web: true) }
    assert_equal 2, @requests.size
    assert_nil @requests.last["tools"]
  end

  test "#call should share the attempt budget across tool schema and correction fallbacks" do
    stub_completions(rejection(param: "tools"), rejection, completion("not JSON"), completion('{"items":[]}'))

    assert_equal({ "items" => [] }, call(web: true).payload)
    assert_raises(LlmClient::Timeout) { call }
    assert_equal 4, @requests.size
    assert_equal 40, LlmUsage.sum(:input_tokens)
  end
end
