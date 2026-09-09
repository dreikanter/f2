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

  def use_external_search
    search = create(:search_credential, :active, user: credential.user)
    @context = LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader,
                                         model: "future-model", purpose: :preview, search_credential: search)
    search
  end

  def function_reply(name: LlmClient::Tools::WebFetch.new.name, arguments: { url: "ftp://example.com" }.to_json, id: "call-1", usage: true)
    reply = response(nil)
    body = JSON.parse(reply[:body])
    body["output"] = [
      { "type" => "reasoning", "id" => "reason-1", "summary" => [], "encrypted_content" => "opaque-reasoning" },
      { "type" => "function_call", "name" => name, "call_id" => id, "arguments" => arguments }
    ]
    body.delete("usage") unless usage
    reply.merge(body: body.to_json)
  end

  test "#call should use a bounded native request with the exact unregistered model and no external credentials" do
    stub_responses(response("Original joke"))

    assert_equal "Original joke", gather.payload

    request = @requests.sole
    assert_equal "future-model", request["model"]
    assert_equal [{ "type" => "web_search" }], request["tools"]
    assert_equal 2, request["max_tool_calls"]
    assert_equal "auto", request["tool_choice"]
    assert_same false, request["store"]
    assert_equal 1_024, request["max_output_tokens"]
    assert_nil request["reasoning"]
    assert_nil request["text"]
    assert_includes request["instructions"], "create it directly"
    assert_equal 2, context.tool_budget.spent
    assert_equal 0, LlmUsage.sole.retrieval["search_calls"]
    assert_not_nil LlmUsage.sole.cost_estimate_cents
  end

  test "#call should use Responses for standalone formatting without assuming Chat Completions support" do
    stub_responses(response('{"items":[]}'))

    result = client.call(context, prompt: "Format supplied facts", output_schema: SCHEMA)

    assert_equal({ "items" => [] }, result.payload)
    assert_equal "future-model", @requests.sole["model"]
    assert_nil @requests.sole["tools"]
    assert_nil @requests.sole["reasoning"]
    assert_equal "json_schema", @requests.sole.dig("text", "format", "type")
    assert_not_requested :post, "https://api.openai.com/v1/chat/completions"
  end

  test "#call should keep a timed out Responses formatting charge unknown" do
    context.responses_api = true
    stub_request(:post, ENDPOINT).to_raise(Faraday::TimeoutError.new("execution expired"))

    assert_raises(LlmClient::Timeout) do
      client.call(context, prompt: "Format supplied facts", output_schema: SCHEMA, web: false)
    end

    assert_equal "timeout", LlmUsage.sole.outcome
    assert_same false, LlmUsage.sole.retrieval["token_usage_reported"]
    assert_nil LlmUsage.sole.cost_estimate_cents
    assert_requested :post, ENDPOINT, times: 1
  end

  test "#load should carry native citations into a separate structure request and account for both calls" do
    citation = { type: "url_citation", url: "https://example.com/news", title: "News", start_index: 0, end_index: 4 }
    items = [{ "body" => "News https://example.com/news", "source_url" => nil }]
    stub_responses(response("News", search: true, annotations: [citation]), response({ items: items }.to_json))
    feed = create(:feed, user: credential.user, ai_credential: credential, ai_model: "future-model",
                         feed_profile_key: "llm", search_credential: nil, params: { "prompt" => "Find current news" })

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
    assert_equal 0, Event.where(type: WebSearchUsage::EVENT_TYPE).count
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

  test "#call should recognize a search rejection naming the selected model" do
    stub_responses(rejection(code: nil, message: "Tool 'web_search' is not supported with future-model."), response("Original joke"))

    assert_equal "Original joke", gather.payload
    assert_nil @requests[1]["tools"]
  end

  test "#call should not retry another tool rejection after native tools are removed" do
    stub_responses(rejection)

    assert_raises(LlmClient::ProviderError) { gather }
    assert_equal 2, @requests.size
    assert_nil @requests[1]["tools"]
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

  test "#call should keep an explicit external selection on Responses without forcing reasoning" do
    use_external_search
    stub_responses(response("Original joke"))

    assert_equal "Original joke", gather.payload

    request = @requests.sole
    assert_equal 2, request["tools"].size
    assert request["tools"].all? { |tool| tool["type"] == "function" }
    assert_equal %w[query url], request["tools"].flat_map { |tool| tool["parameters"]["required"] }.sort
    assert request["tools"].all? { |tool| tool["parameters"]["additionalProperties"] == false }
    assert_nil request["reasoning"]
    assert_nil request["reasoning_effort"]
    assert_nil request["max_tool_calls"]
    assert_not_requested :post, "https://api.openai.com/v1/chat/completions"
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
    feed = create(:feed, user: credential.user, ai_credential: credential, feed_profile_key: "llm",
                         search_credential: nil, params: { "prompt" => "News" })

    assert_raises(Loader::Error) { Loader::LlmLoader.new(feed).load }
    assert_equal "schema_error", LlmUsage.sole.outcome
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
    assert_same false, LlmUsage.sole.retrieval["token_usage_reported"]
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
    stub_request(:post, ENDPOINT).to_raise(Faraday::TimeoutError.new("execution expired"))

    assert_raises(LlmClient::Timeout) { gather }

    assert_nil LlmUsage.sole.cost_estimate_cents
    assert_nil LlmUsage.sole.retrieval["search_calls"]
    assert_requested :post, ENDPOINT, times: 1
  end
  test "#call should replay function results and encrypted reasoning while accumulating every completion" do
    use_external_search
    stub_responses(function_reply, response("Available answer"))

    assert_equal "Available answer", gather.payload

    assert_equal 2, @requests.size
    assert_equal ["future-model"], @requests.pluck("model").uniq
    assert @requests.all? { |request| request["store"] == false && request["max_output_tokens"] == 1_024 }
    history = @requests.last["input"]
    assert_equal %w[user], history.filter_map { |item| item["role"] }
    assert_equal "opaque-reasoning", history.find { |item| item["type"] == "reasoning" }["encrypted_content"]
    result = history.find { |item| item["type"] == "function_call_output" }
    assert_equal "call-1", result["call_id"]
    assert_includes result["output"], "Refused"
    assert_equal 1, context.tool_budget.spent
    usage = LlmUsage.sole
    assert_equal 2, usage.retrieval["completion_calls"]
    assert_equal 160, usage.input_tokens
    assert_equal 60, usage.output_tokens
    assert_equal 40, usage.cache_read_tokens
    assert_same true, usage.retrieval["token_usage_reported"]
    assert_equal "0.0284".to_d, usage.cost_estimate_cents
  end

  test "#call should retain partial tokens and unknown cost when a continuation fails" do
    use_external_search
    stub_responses(function_reply, rejection(param: "tools"))

    assert_raises(LlmClient::ProviderError) { gather }

    assert_equal 2, @requests.size
    assert_equal 80, LlmUsage.sole.input_tokens
    assert_equal 30, LlmUsage.sole.output_tokens
    assert_same false, LlmUsage.sole.retrieval["token_usage_reported"]
    assert_nil LlmUsage.sole.cost_estimate_cents
    assert_not context.tools_disabled
  end

  test "#call should preserve missing usage from an earlier tool round" do
    use_external_search
    stub_responses(function_reply(usage: false), response("Available answer"))

    gather

    assert_equal 80, LlmUsage.sole.input_tokens
    assert_nil LlmUsage.sole.cost_estimate_cents
    assert_same false, LlmUsage.sole.retrieval["token_usage_reported"]
  end

  test "#call should remove rejected external tools once and use supplied pages without changing endpoint" do
    use_external_search
    stub_responses(rejection, response("Supplied fact"))
    stub_request(:get, "https://example.com/post").to_return(body: "<p>Supplied fact</p>")

    result = Socket.stub(:getaddrinfo, [["AF_INET", 0, "example.com", "93.184.216.34"]]) do
      gather("Summarize https://example.com/post")
    end

    assert_equal "Supplied fact", result.payload
    assert_equal 2, @requests.size
    assert_nil @requests.last["tools"]
    assert_includes @requests.last["input"], "Supplied fact"
    assert_equal %w[provider_error success], LlmUsage.order(:created_at).pluck(:outcome)
    assert_equal %w[external limited], LlmUsage.order(:created_at).map { |usage| usage.retrieval["mode"] }
    assert_not_requested :post, "https://api.openai.com/v1/chat/completions"
  end

  test "#call should bound external tool rejection and leave malformed calls visible" do
    [rejection, rejection(param: "tools", code: "invalid_parameter"), function_reply(name: "unknown_tool"),
     function_reply(arguments: "not JSON"), function_reply(arguments: '{"url":42}'), function_reply(id: nil)].each_with_index do |reply, index|
      use_external_search
      stub_responses(reply)

      assert_raises(LlmClient::ProviderError) { gather }
      assert_equal index.zero? ? 2 : 1, @requests.size
      assert_not_requested :post, "https://api.openai.com/v1/chat/completions"
    end
  end

  test "#call should charge tool continuations against the shared attempt allowance before doing more search" do
    use_external_search
    stub_responses(function_reply)

    assert_raises(LlmClient::Timeout) { gather }

    assert_equal 4, @requests.size
    assert_equal 3, context.tool_budget.spent
    assert_equal 4, LlmUsage.sole.retrieval["completion_calls"]
    assert_equal 320, LlmUsage.sole.input_tokens
    assert_equal "timeout", LlmUsage.sole.outcome
    assert_not_nil LlmUsage.sole.cost_estimate_cents
  end

  test "#call should honor a previously exhausted tool allowance" do
    use_external_search
    10.times { context.tool_budget.claim }
    stub_responses(function_reply)

    assert_raises(LlmClient::ProviderError) { gather }

    assert_equal 1, @requests.size
    assert_equal 80, LlmUsage.sole.input_tokens
    assert_equal 11, context.tool_budget.spent
  end

  test "#execute should search and fetch through Responses and attribute preview costs to the saved feed" do
    search = use_external_search
    source = "https://example.com/news"
    tools = LlmClient::Adapter::OpenAi.new.web_tools(search_provider: search.web_search_provider,
                                                   search_credential: search, budget: context.tool_budget)
    first = function_reply(name: tools.first.name, arguments: { query: "release news" }.to_json)
    body = JSON.parse(first[:body])
    body["output"] << { type: "function_call", name: tools.last.name, call_id: "fetch-1", arguments: { url: source }.to_json }
    items = [{ body: "Verified release facts", source_url: source }]
    stub_responses(first.merge(body: body.to_json), response({ items: items }.to_json))
    search_request = stub_request(:post, "https://google.serper.dev/search")
      .with(headers: { "X-API-KEY" => search.credential_data["api_key"] }, body: { q: "release news", num: 5 }.to_json)
      .to_return(headers: { "Content-Type" => "application/json" }, body: {
        organic: [{ title: "Release", link: source, snippet: "Release facts" }]
      }.to_json)
    fetch_request = stub_request(:get, source).to_return(body: "<p>Verified release facts</p>")
    feed = create(:feed, :draft, user: credential.user, ai_credential: credential, ai_model: "future-model",
                         search_credential: search, feed_profile_key: "llm", params: { "prompt" => "Find release news" })
    preview = create(:feed_preview, user: feed.user, feed: feed, ai_credential: credential, ai_model: feed.ai_model,
                                    search_credential: search, feed_profile_key: "llm", params: feed.params)

    assert_no_difference -> { Post.count } do
      Socket.stub(:getaddrinfo, [["AF_INET", 0, "example.com", "93.184.216.34"]]) do
        FeedPreviewWorkflow.new(preview, run_id: preview.run_id).execute
      end
    end

    assert preview.reload.ready?
    assert_includes preview.posts_data.sole["content"], "Verified release facts"
    assert_includes preview.posts_data.sole["content"], source
    assert_equal 2, @requests.size
    assert_includes @requests.last["input"].to_json, "Verified release facts"
    assert_equal "json_schema", @requests.last.dig("text", "format", "type")
    usage = feed.llm_usages.sole
    assert_equal 2, usage.retrieval["completion_calls"]
    assert_equal "external", usage.retrieval["mode"]
    assert_equal "0.0284".to_d, usage.cost_estimate_cents
    event = feed.events.find_by!(type: "feed_preview")
    assert_equal [usage], event.references.grep(LlmUsage)
    assert_equal 1, event.references.grep(Event).count { |reference| reference.type == WebSearchUsage::EVENT_TYPE }
    assert_requested search_request, times: 1
    assert_requested fetch_request, times: 1
  end

  test "#call should preserve an external selection after a Responses endpoint rejection" do
    use_external_search
    stub_responses(rejection(param: "model", message: "This model is not supported in the Responses API"))
    chat = stub_request(:post, "https://api.openai.com/v1/chat/completions").with do |request|
      body = JSON.parse(request.body)
      body["model"] == "future-model" && body["tools"].size == 2 && !body.key?("reasoning_effort")
    end.to_return(headers: { "Content-Type" => "application/json" }, body: {
      choices: [{ message: { role: "assistant", content: "Available answer" } }], usage: { prompt_tokens: 20, completion_tokens: 10 }
    }.to_json)

    assert_equal "Available answer", gather.payload
    assert_same false, context.responses_api
    assert_equal %w[provider_error success], LlmUsage.order(:created_at).pluck(:outcome)
    assert_equal %w[external external], LlmUsage.order(:created_at).map { |usage| usage.retrieval["mode"] }
    assert_requested chat, times: 1
  end

  test "#call should continue on Responses with limited content when external tools are known unavailable" do
    use_external_search
    credential.update!(available_models: [{ "id" => context.model, "metadata" => { "tool_call" => false } }])
    stub_responses(response("Available answer"))

    assert_equal "Available answer", gather.payload
    assert_nil @requests.sole["tools"]
    assert_equal "limited", LlmUsage.sole.retrieval["mode"]
  end

  test "#call should keep rejected search credentials visible while allowing a final answer" do
    search = use_external_search
    tool = LlmClient::Tools::WebSearch.new(provider: search.web_search_provider, credential: search)
    stub_responses(function_reply(name: tool.name, arguments: '{"query":"release"}'), response("Available answer"))
    stub_request(:post, "https://google.serper.dev/search").to_return(status: 401, body: "Invalid API key")

    assert_equal "Available answer", gather.payload
    assert search.reload.inactive?
    assert_includes @requests.last["input"].last["output"], "credentials were rejected"
    assert_equal 1, Event.where(type: WebSearchUsage::EVENT_TYPE).count
    assert_equal 2, @requests.size
  end

  test "#call should stop continuations when the original deadline expires" do
    use_external_search
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    clock = ->(*) { now }
    stub_request(:post, ENDPOINT).to_return do
      now += RubyLLM.config.request_timeout + 1
      function_reply
    end

    Process.stub(:clock_gettime, clock) do
      assert_raises(LlmClient::Timeout) { gather }
    end

    assert_requested :post, ENDPOINT, times: 1
    assert_equal 0, context.tool_budget.spent
    assert_equal 80, LlmUsage.sole.input_tokens
    assert_equal "timeout", LlmUsage.sole.outcome
  end
end
