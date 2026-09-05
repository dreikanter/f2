require "test_helper"

class LlmClient::MoonshotSearchTest < ActiveSupport::TestCase
  CHAT = "https://api.moonshot.ai/v1/chat/completions".freeze
  FORMULA = "https://api.moonshot.ai/v1/formulas/moonshot/web-search:latest".freeze
  ENCRYPTED = "----MOONSHOT ENCRYPTED BEGIN----opaque search evidence----MOONSHOT ENCRYPTED END----".freeze
  TOOL = { type: "function", function: { name: "web_search", description: "Search the web", parameters: {
    type: "object", properties: { query: { type: "string" } }, required: ["query"]
  } } }.freeze

  setup do
    stub_request(:get, "#{FORMULA}/tools").with(headers: { "Authorization" => "Bearer kimi-test" })
      .to_return(json({ tools: [TOOL] }))
  end

  def credential
    @credential ||= create(:ai_credential, :active, provider: "moonshot", credential_data: { "api_key" => "kimi-test" },
                            available_models: [{ "id" => "future-kimi", "metadata" => {
                              "max_output_tokens" => 1_024, "structured_output" => false,
                              "pricing" => { "input" => 1, "output" => 2, "cache_read" => 0.1 }
                            } }])
  end

  def context
    @context ||= LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader,
                                           model: "future-kimi", purpose: :preview)
  end

  def gather
    LlmClient.new(credential).call(context, prompt: "Invent a joke please", output_schema: nil,
                                 system: Loader::LlmPrompts::GATHER_SYSTEM, web: true)
  end

  def json(body, status: 200)
    { status: status, headers: { "Content-Type" => "application/json" }, body: body.to_json }
  end

  def completion(content = nil, calls: [], usage: true, finish: nil)
    message = { role: "assistant", content: content }
    message.merge!(tool_calls: calls, reasoning_content: "Preserve this reasoning") if calls.any?
    body = { choices: [{ message: message, finish_reason: finish || (calls.any? ? "tool_calls" : "stop") }] }
    body[:usage] = { prompt_tokens: 100, completion_tokens: 30, prompt_tokens_details: { cached_tokens: 20 } } if usage
    json(body)
  end

  def search_call(id = "search-1", name: "web_search", arguments: '{"query": "recent Ruby release"}')
    { id: id, type: "function", function: { name: name, arguments: arguments } }
  end

  def stub_chat(*replies)
    @requests = []
    stub_request(:post, CHAT).with(headers: { "Authorization" => "Bearer kimi-test" }) do |request|
      @requests << JSON.parse(request.body)
      true
    end.to_return(*replies)
  end

  def stub_search
    stub_request(:post, "#{FORMULA}/fibers").with(headers: { "Authorization" => "Bearer kimi-test" })
      .to_return(json({ status: "succeeded", context: { encrypted_output: ENCRYPTED } }))
  end

  test "#call should offer provider search to an unregistered model without forcing its use" do
    stub_chat(completion("An original joke"))

    assert_equal "An original joke", gather.payload

    request = @requests.sole
    assert_equal "future-kimi", request["model"]
    assert_equal JSON.parse(TOOL.to_json), request["tools"].sole
    assert_equal "auto", request["tool_choice"]
    assert_equal 1_024, request["max_tokens"]
    assert_equal "system", request["messages"].first["role"]
    assert_nil request["temperature"]
    assert_nil request["thinking"]
    assert_nil request["response_format"]
    assert_not context.responses_api
    assert_equal 0, LlmUsage.sole.retrieval["search_calls"]
    assert_not_nil LlmUsage.sole.cost_estimate_cents
    assert_not_requested :post, "#{FORMULA}/fibers"
  end

  test "#execute should retain reasoning and opaque results while attributing all tokens to the saved feed preview" do
    stub_search
    stub_chat(completion(calls: [search_call]), completion("Release: https://example.com/release"),
              completion('{"items":[{"body":"Release","source_url":"https://example.com/release"}]}'))
    feed = create(:feed, :draft, user: credential.user, ai_credential: credential, ai_model: "future-kimi",
                         feed_profile_key: "llm", params: { "prompt" => "Find a recent release" })
    preview = create(:feed_preview, user: feed.user, feed: feed, ai_credential: credential, ai_model: feed.ai_model,
                                    feed_profile_key: "llm", params: feed.params)

    assert_no_difference -> { Post.count } do
      FeedPreviewWorkflow.new(preview, run_id: preview.run_id).execute
    end

    assert preview.reload.ready?
    assert_includes preview.posts_data.sole["content"], "https://example.com/release"
    followup = @requests[1]
    assert_equal "Preserve this reasoning", followup["messages"][2]["reasoning_content"]
    assert_equal ENCRYPTED, followup["messages"][3]["content"]
    assert_equal "search-1", followup["messages"][3]["tool_call_id"]
    assert_equal "none", followup["tool_choice"]
    assert_equal @requests[0]["tools"], followup["tools"]
    assert_nil @requests[2]["tools"]
    assert_includes @requests[2]["messages"][1]["content"], "https://example.com/release"
    assert_equal ["future-kimi"], @requests.pluck("model").uniq
    event = feed.events.find_by!(type: "feed_preview")
    usages = feed.llm_usages.order(:created_at)
    assert_equal usages.pluck(:id).sort, event.references.grep(LlmUsage).map(&:id).sort
    assert_equal 2, usages.count
    assert_equal 160, usages.first.input_tokens
    assert_equal 40, usages.first.cache_read_tokens
    assert_equal 60, usages.first.output_tokens
    assert_equal 2, usages.first.retrieval["completion_calls"]
    assert_equal 1, usages.first.retrieval["search_calls"]
    assert_nil usages.first.cost_estimate_cents
    assert_not_nil usages.last.cost_estimate_cents
    assert_requested :post, "#{FORMULA}/fibers", body: search_call[:function].to_json, times: 1
  end

  test "#call should cap search executions and answer every proposed tool call" do
    stub_search
    stub_chat(completion(calls: 3.times.map { |i| search_call("search-#{i}") }), completion("Available evidence"))

    assert_equal "Available evidence", gather.payload

    assert_requested :post, "#{FORMULA}/fibers", times: 2
    assert_equal 2, context.tool_budget.spent
    results = @requests.last["messages"].select { |message| message["role"] == "tool" }
    assert_equal 3, results.size
    assert_includes results.last["content"], "Tool budget spent"
    assert_equal 2, LlmUsage.sole.retrieval["search_calls"]
  end

  test "#call should share the remaining tool budget with supplied page fetching" do
    context.tool_budget.reserve(LlmClient::ToolBudget::ROUNDS - 1)
    stub_search
    stub_chat(completion(calls: [search_call, search_call("search-2")]), completion("Available evidence"))

    gather

    assert_requested :post, "#{FORMULA}/fibers", times: 1
    assert_equal LlmClient::ToolBudget::ROUNDS, context.tool_budget.spent
  end

  test "#call should stop a model that ignores the final no-tools request" do
    stub_search
    stub_chat(completion(calls: [search_call]), completion(calls: [search_call("again")]))

    assert_equal "", gather.payload
    assert_requested :post, CHAT, times: 2
    assert_requested :post, "#{FORMULA}/fibers", times: 1
  end

  test "#call should never execute another formula requested by the model" do
    stub_chat(completion(calls: [search_call(name: "code_runner")]), completion("An original joke"))

    assert_equal "An original joke", gather.payload
    assert_equal 0, LlmUsage.sole.retrieval["search_calls"]
    assert_not_requested :post, "#{FORMULA}/fibers"
  end

  test "#call should fall back when free search discovery is unavailable without recording a paid attempt" do
    stub_request(:get, "#{FORMULA}/tools").to_return(json({ error: { message: "Not found" } }, status: 404))
    stub_chat(completion("An original joke"))

    assert_equal "An original joke", gather.payload
    assert_equal 1, LlmUsage.count
    assert_equal "limited", LlmUsage.sole.retrieval["mode"]
    assert_includes @requests.sole["messages"][0]["content"], "Web search is unavailable"
    assert_equal "future-kimi", @requests.sole["model"]
    assert credential.reload.active?
  end

  test "#call should fall back after explicit tool rejection without excluding the model" do
    rejection = json({ error: { message: "Tools are not supported for this model", param: "tools", code: "unsupported_parameter" } }, status: 400)
    stub_chat(rejection, completion("An original joke"))

    assert_equal "An original joke", gather.payload
    assert_nil @requests.last["tools"]
    assert_equal %w[provider_error success], LlmUsage.order(:created_at).pluck(:outcome)
    assert_nil LlmUsage.order(:created_at).first.cost_estimate_cents
    assert credential.reload.supports_model?("future-kimi")
  end

  test "#call should let Kimi finish with limited content after a failed search result" do
    stub_request(:post, "#{FORMULA}/fibers").to_return(json({ status: "failed" }))
    stub_chat(completion(calls: [search_call]), completion("An original joke"))

    assert_equal "An original joke", gather.payload
    assert_includes @requests.last["messages"].last["content"], "Web search is unavailable"
    assert_equal ["failed"], LlmUsage.sole.retrieval["search_statuses"]
    assert_nil LlmUsage.sole.cost_estimate_cents
  end

  test "#call should retain the first completion and search attempt when the final completion fails" do
    stub_search
    stub_chat(completion(calls: [search_call]), json({ error: { message: "Unavailable" } }, status: 500))

    assert_raises(LlmClient::ProviderError) { gather }
    assert_requested :post, CHAT, times: 2
    assert_equal 80, LlmUsage.sole.input_tokens
    assert_equal 1, LlmUsage.sole.retrieval["search_calls"]
    assert_equal false, LlmUsage.sole.retrieval["token_usage_reported"]
    assert_nil LlmUsage.sole.cost_estimate_cents
  end

  test "#call should retain model tokens and a possibly billed search after a fiber timeout" do
    stub_request(:post, "#{FORMULA}/fibers").to_raise(Faraday::TimeoutError.new("execution expired"))
    stub_chat(completion(calls: [search_call]))

    assert_raises(LlmClient::Timeout) { gather }
    assert_requested :post, CHAT, times: 1
    assert_requested :post, "#{FORMULA}/fibers", times: 1
    assert_equal 80, LlmUsage.sole.input_tokens
    assert_equal 1, LlmUsage.sole.retrieval["search_calls"]
    assert_nil LlmUsage.sole.cost_estimate_cents
  end

  test "#call should mark missing token usage unknown even if no search was made" do
    stub_chat(completion("An original joke", usage: false))

    gather

    assert_equal false, LlmUsage.sole.retrieval["token_usage_reported"]
    assert_nil LlmUsage.sole.cost_estimate_cents
  end

  test "#call should keep an explicit external search selection" do
    search = create(:search_credential, :active, user: credential.user)
    @context = LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader, model: "future-kimi", search_credential: search)
    stub_chat(completion("An original joke"))

    gather

    assert_equal "external", LlmUsage.sole.retrieval["mode"]
    assert_not_requested :get, "#{FORMULA}/tools"
    assert_not_requested :post, "#{FORMULA}/fibers"
  end

  { 401 => LlmClient::AuthError, 429 => LlmClient::RateLimited, 500 => LlmClient::ProviderError }.each do |status, error|
    test "#call should not retry or downgrade HTTP #{status}" do
      stub_chat(json({ error: { message: "Request failed", type: "test_error" } }, status: status))

      assert_raises(error) { gather }
      assert_requested :post, CHAT, times: 1
      assert_equal 1, LlmUsage.count
      assert_nil LlmUsage.sole.cost_estimate_cents
    end
  end
end
