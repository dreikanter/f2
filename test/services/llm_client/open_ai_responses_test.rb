require "test_helper"

class LlmClient::OpenAiResponsesTest < ActiveSupport::TestCase
  ENDPOINT = "https://api.openai.com/v1/responses"
  SCHEMA = { "type" => "object", "properties" => { "items" => { "type" => "array" } }, "required" => ["items"] }.freeze

  def credential
    @credential ||= create(:ai_credential, :active, provider: "openai", credential_data: { "api_key" => "native-test" },
                            available_models: [{ "id" => "future-model", "metadata" => {
                              "max_output_tokens" => 1_024, "pricing" => { "input" => 1, "output" => 2, "cache_read" => 0.1 }
                            } }])
  end

  def context
    @context ||= LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader, model: "future-model", purpose: :preview)
  end

  def client
    @client ||= LlmClient.new(credential)
  end

  def response(text, search: false, status: "completed", annotations: [])
    output = [{ type: "message", role: "assistant", content: [{ type: "output_text", text: text, annotations: annotations }] }]
    output.unshift(type: "web_search_call", status: "completed", action: { type: "search" }) if search
    { status: 200, headers: { "Content-Type" => "application/json" }, body: {
      status: status, output: output, usage: { input_tokens: 100, input_tokens_details: { cached_tokens: 20 }, output_tokens: 30 }
    }.to_json }
  end

  def rejection(param: "tools", code: "unsupported_parameter", message: "Unsupported parameter", status: 400)
    { status: status, headers: { "Content-Type" => "application/json" }, body: {
      error: { type: "invalid_request_error", param: param, code: code, message: message }
    }.to_json }
  end

  def stub_responses(*responses)
    @requests = []
    stub_request(:post, ENDPOINT).with(headers: { "Authorization" => "Bearer native-test" }) do |request|
      @requests << JSON.parse(request.body)
      true
    end.to_return(*responses)
  end

  def gather(prompt = "Invent a joke please")
    client.call(context, prompt: prompt, system: Loader::LlmPrompts::GATHER_SYSTEM, output_schema: nil, web: true)
  end

  test "#call should use a bounded native request with the exact unregistered model and no external credentials" do
    stub_responses(response("Original joke"))

    assert_equal "Original joke", gather.payload

    request = @requests.sole
    assert_equal "future-model", request["model"]
    assert_equal [{ "type" => "web_search" }], request["tools"]
    assert_equal 2, request["max_tool_calls"]
    assert_equal "auto", request["tool_choice"]
    assert_equal false, request["store"]
    assert_equal 1_024, request["max_output_tokens"]
    assert_nil request["reasoning"]
    assert_nil request["text"]
    assert_includes request["instructions"], "create it directly"
    assert_equal 2, context.tool_budget.spent
    assert_equal 0, LlmUsage.sole.retrieval["search_calls"]
    assert_not_nil LlmUsage.sole.cost_estimate_cents
  end

  test "#load should carry native citations into a separate structure request and account for both calls" do
    citation = { type: "url_citation", url: "https://example.com/news", title: "News", start_index: 0, end_index: 4 }
    items = [{ "body" => "News https://example.com/news", "source_url" => nil }]
    stub_responses(response("News", search: true, annotations: [citation]), response({ items: items }.to_json))
    feed = create(:feed, user: credential.user, ai_credential: credential, ai_model: "future-model",
                         feed_profile_key: "llm", params: { "prompt" => "Find current news" })

    assert_equal items, Loader::LlmLoader.new(feed, purpose: :preview).load

    assert_equal 2, @requests.size
    assert_includes @requests[1]["input"], citation[:url]
    assert_includes @requests[1]["input"], "Citations for this passage"
    assert_includes @requests[1]["instructions"], "Preserve citations"
    assert_nil @requests[1]["tools"]
    assert_equal "json_schema", @requests[1].dig("text", "format", "type")
    assert_equal ["future-model"], @requests.pluck("model").uniq
    usages = LlmUsage.order(:created_at)
    assert_equal [80, 80], usages.pluck(:input_tokens)
    assert_equal [20, 20], usages.pluck(:cache_read_tokens)
    assert_equal [30, 30], usages.pluck(:output_tokens)
    assert_equal 1, usages.first.retrieval["search_calls"]
    assert_nil usages.first.cost_estimate_cents
    assert_not_nil usages.last.cost_estimate_cents
    assert_equal 0, WebSearchUsage.count
  end

  test "#call should fall back to supplied pages after explicit native search rejection on the same endpoint" do
    stub_responses(rejection, response("Retrieved fact"))
    stub_request(:get, "https://example.com/post").to_return(body: "<p>Retrieved fact</p>")

    result = Socket.stub(:getaddrinfo, [["AF_INET", 0, "example.com", "93.184.216.34"]]) do
      gather("Summarize https://example.com/post")
    end

    assert_equal "Retrieved fact", result.payload
    assert_nil @requests[1]["tools"]
    assert_includes @requests[1]["input"], "Retrieved fact"
    assert_includes @requests[1]["instructions"], "Web search is unavailable"
    assert_equal %w[provider_error success], LlmUsage.order(:created_at).pluck(:outcome)
    assert_equal "limited", LlmUsage.order(:created_at).last.retrieval["mode"]
    assert credential.reload.active?
    assert_requested :get, "https://example.com/post", times: 1
  end

  test "#call should preserve the schema fallback and correction without searching again" do
    stub_responses(response("Original joke"), rejection(param: "text.format"), response("not JSON"), response('{"items":[]}'))
    gather

    result = client.call(context, prompt: "Original joke", output_schema: SCHEMA)

    assert_equal({ "items" => [] }, result.payload)
    assert_equal 4, @requests.size
    assert @requests.drop(1).all? { |request| request["tools"].nil? }
    assert_nil @requests[2]["text"]
    assert_equal %w[success provider_error schema_error success], LlmUsage.order(:created_at).pluck(:outcome)
    assert_raises(LlmClient::Timeout) { gather }
    assert_equal 4, @requests.size
  end

  test "#call should fall back to Chat Completions only for an explicit Responses model rejection" do
    stub_responses(rejection(param: "model", message: "This model is not supported in the Responses API"))
    chat = stub_request(:post, "https://api.openai.com/v1/chat/completions").with do |request|
      body = JSON.parse(request.body)
      body["model"] == "future-model" && body["tools"].size == 1
    end.to_return(headers: { "Content-Type" => "application/json" }, body: {
      choices: [{ message: { role: "assistant", content: "Original joke" } }], usage: { prompt_tokens: 20, completion_tokens: 10 }
    }.to_json)

    assert_equal "Original joke", gather.payload
    assert_requested chat, times: 1
    assert_equal 1, @requests.size
  end

  test "#call should keep an explicit external selection on the existing tool transport" do
    search = create(:search_credential, :active, user: credential.user)
    @context = LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader,
                                         model: "future-model", search_credential: search)
    chat = stub_request(:post, "https://api.openai.com/v1/chat/completions").with do |request|
      JSON.parse(request.body)["tools"].size == 2
    end.to_return(headers: { "Content-Type" => "application/json" }, body: {
      choices: [{ message: { role: "assistant", content: "Original joke" } }], usage: { prompt_tokens: 20, completion_tokens: 10 }
    }.to_json)

    assert_equal "Original joke", gather.payload
    assert_requested chat, times: 1
    assert_not_requested :post, ENDPOINT
    assert_equal "external", LlmUsage.sole.retrieval["mode"]
  end

  test "#call should honor the remaining shared tool budget" do
    7.times { context.tool_budget.claim }
    stub_responses(response("News", search: true), response("Original joke"))

    gather
    gather

    assert_equal 1, @requests[0]["max_tool_calls"]
    assert_nil @requests[1]["tools"]
    assert_equal 8, context.tool_budget.spent
  end

  test "#call should preserve paid usage and stop on incomplete output" do
    stub_responses(response("Truncated post", search: true, status: "incomplete"))

    assert_raises(LlmClient::ProviderError) { gather }

    assert_equal 1, @requests.size
    usage = LlmUsage.sole
    assert_equal 80, usage.input_tokens
    assert_equal 30, usage.output_tokens
    assert_equal 1, usage.retrieval["search_calls"]
    assert_nil usage.cost_estimate_cents
    assert_equal "provider_error", usage.outcome
  end

  test "#load should not turn citation metadata into gathered content" do
    stub_responses(response("", search: true, annotations: [{ type: "url_citation", url: "https://example.com" }]))
    feed = create(:feed, user: credential.user, ai_credential: credential, feed_profile_key: "llm", params: { "prompt" => "News" })

    assert_equal [], Loader::LlmLoader.new(feed).load
    assert_equal 1, @requests.size
    assert_nil LlmUsage.sole.cost_estimate_cents
  end

  test "#call should use native search with an inactive external credential and unknown function support" do
    search = create(:search_credential, :inactive, user: credential.user)
    @context = LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader,
                                         model: "future-model", search_credential: search)
    credential.update!(available_models: [{ "id" => "future-model", "metadata" => { "tool_call" => false } }])
    stub_responses(response("Original joke"))

    assert_equal "Original joke", gather.payload
    assert_equal [{ "type" => "web_search" }], @requests.sole["tools"]
  end

  test "#call should keep missing token usage unknown even when no search calls are reported" do
    reply = response("Original joke")
    reply[:body] = JSON.parse(reply[:body]).except("usage").to_json
    stub_responses(reply)

    gather

    assert_nil LlmUsage.sole.cost_estimate_cents
    assert_equal false, LlmUsage.sole.retrieval["token_usage_reported"]
  end

  test "#call should not retry auth rate limit server malformed tool or unknown model errors" do
    [
      [rejection(status: 401), LlmClient::AuthError],
      [rejection(status: 429), LlmClient::RateLimited],
      [rejection(status: 500), LlmClient::ProviderError],
      [rejection(code: "invalid_parameter", message: "Invalid tools declaration"), LlmClient::ProviderError],
      [rejection(param: "model", code: "model_not_found", message: "Model does not exist", status: 404), LlmClient::ProviderError]
    ].each do |error_response, error_class|
      @context = nil
      stub_responses(error_response)

      assert_difference -> { LlmUsage.count }, 1 do
        assert_raises(error_class) { gather }
      end
      assert_equal 1, @requests.size
    end
  end

  test "#call should mark hosted search cost unknown when the connection times out" do
    stub_request(:post, ENDPOINT).to_timeout

    assert_raises(LlmClient::Timeout) { gather }

    assert_nil LlmUsage.sole.cost_estimate_cents
    assert_nil LlmUsage.sole.retrieval["search_calls"]
    assert_requested :post, ENDPOINT, times: 1
  end
end
