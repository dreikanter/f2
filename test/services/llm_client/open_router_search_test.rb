require "test_helper"

class LlmClient::OpenRouterSearchTest < ActiveSupport::TestCase
  ENDPOINT = "https://openrouter.ai/api/v1/chat/completions".freeze
  SOURCE = "https://example.com/release".freeze

  def credential
    @credential ||= create(:ai_credential, :active, provider: "openrouter", credential_data: { "api_key" => "router-test" },
                            available_models: [{ "id" => "example/future-model", "metadata" => {
                              "max_output_tokens" => 1_024, "structured_output" => false,
                              "pricing" => { "input" => 1, "output" => 2, "cache_read" => 0.1, "cache_write" => 1.25 }
                            } }])
  end

  def context
    @context ||= LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader,
                                           model: "example/future-model", purpose: :preview)
  end

  def gather(prompt = "Invent a joke please")
    LlmClient.new(credential).call(context, prompt: prompt, output_schema: nil,
                                 system: Loader::LlmPrompts::GATHER_SYSTEM, web: true)
  end

  def json(body, status: 200)
    { status: status, headers: { "Content-Type" => "application/json" }, body: body.to_json }
  end

  def citation(url = SOURCE)
    { type: "url_citation", url_citation: { url: url, title: "Release", content: "Release facts", start_index: 0, end_index: 13 } }
  end

  def reply(text = "An original joke", annotations: [], finish: "stop", calls: [], usage: {})
    body = { choices: [{ message: { role: "assistant", content: text, annotations: annotations,
                                   reasoning: "Private reasoning", tool_calls: calls }, finish_reason: finish }] }
    body[:usage] = { prompt_tokens: 100, completion_tokens: 30,
                     prompt_tokens_details: { cached_tokens: 20, cache_write_tokens: 10 },
                     server_tool_use: { web_search_requests: 1 }, cost: 0.017, is_byok: false }.merge(usage) if usage
    json(body)
  end

  def rejection(message, status: 400, **detail)
    json({ error: { message: message }.merge(detail) }, status: status)
  end

  def stub_chat(*responses)
    @requests = []
    stub_request(:post, ENDPOINT).with(headers: { "Authorization" => "Bearer router-test" }) do |request|
      @requests << JSON.parse(request.body)
      true
    end.to_return(*responses)
  end

  test "#call should offer bounded native-first search to an exact unregistered model without forcing a search" do
    stub_chat(reply)

    assert_equal "An original joke", gather.payload

    request = @requests.sole
    assert_equal "example/future-model", request["model"]
    assert_equal [{ "type" => "openrouter:web_search", "parameters" => {
      "engine" => "auto", "max_uses" => 2, "max_results" => 3, "max_total_results" => 6, "max_characters" => 2_000
    } }], request["tools"]
    assert_equal 2, request["max_tool_calls"]
    assert_equal({ "require_parameters" => true, "allow_fallbacks" => false }, request["provider"])
    assert_equal 1_024, request["max_tokens"]
    %w[temperature reasoning tool_choice response_format plugins].each { |key| assert_nil request[key] }
    assert_equal "system", request["messages"].first["role"]
    assert_includes request["messages"].first["content"], "create it directly"
    assert_equal "Invent a joke please", request["messages"].last["content"]
    usage = LlmUsage.sole
    assert_equal "provider", usage.retrieval["mode"]
    assert_equal 1, usage.retrieval["search_calls"]
    assert_equal 1, usage.retrieval["completion_calls"]
    assert_equal 70, usage.input_tokens
    assert_equal 30, usage.output_tokens
    assert_equal 20, usage.cache_read_tokens
    assert_equal 10, usage.cache_write_tokens
    assert_equal 2, usage.cost_estimate_cents
  end

  test "#execute should retain citations and associate all preview usage with the saved feed" do
    stub_chat(reply("Release facts", annotations: [citation]),
              reply('{"items":[{"body":"Release facts","source_url":"https://example.com/release"}]}'))
    feed = create(:feed, :draft, user: credential.user, ai_credential: credential, ai_model: "example/future-model",
                         search_credential: nil, feed_profile_key: "llm", params: { "prompt" => "Find a recent release" })
    preview = create(:feed_preview, user: feed.user, feed: feed, ai_credential: credential, ai_model: feed.ai_model,
                                    feed_profile_key: "llm", params: feed.params)

    assert_no_difference -> { Post.count } do
      FeedPreviewWorkflow.new(preview, run_id: preview.run_id).execute
    end

    assert preview.reload.ready?
    assert_includes preview.posts_data.sole["content"], SOURCE
    assert_equal 2, @requests.size
    assert_nil @requests.last["tools"]
    prompt = @requests.last["messages"].to_json
    assert_includes prompt, "Citations for this passage"
    assert_includes prompt, SOURCE
    assert_not_includes prompt, "Private reasoning"
    usages = feed.llm_usages.order(:created_at)
    event = feed.events.find_by!(type: "feed_preview")
    assert_equal 2, usages.count
    assert_equal usages.pluck(:id).sort, event.references.grep(LlmUsage).map(&:id).sort
    assert_equal ["example/future-model"], usages.pluck(:model).uniq
    assert_equal 2, usages.first.cost_estimate_cents
    assert_equal({}, usages.last.retrieval)
    assert_equal 0, usages.last.cost_estimate_cents
  end

  test "#call should keep missing malformed and BYOK costs unknown even when no search was used" do
    [nil, -1, "0.017", 30_000_000].map { |cost| { cost: cost } }.concat([
      { is_byok: true }, { is_byok: nil }
    ]).each do |usage|
      @context = nil
      stub_chat(reply(usage: usage.merge(server_tool_use: { web_search_requests: 0 })))

      result = gather

      assert_nil LlmUsage.find(result.usage_id).cost_estimate_cents
      assert_equal 1, @requests.size
    end
  end

  test "#call should record a reported total without assuming missing token or query counts are zero" do
    stub_chat(reply(usage: { prompt_tokens: nil, completion_tokens: nil, server_tool_use: nil }))

    gather

    usage = LlmUsage.sole
    assert_equal false, usage.retrieval["token_usage_reported"]
    assert_nil usage.retrieval["search_calls"]
    assert_equal 2, usage.cost_estimate_cents
  end

  test "#call should honor an explicit zero charge but preserve entirely missing usage as unknown" do
    [reply(usage: { cost: 0 }), reply(usage: nil)].each_with_index do |response, index|
      @context = nil
      stub_chat(response)

      usage = LlmUsage.find(gather.usage_id)

      if index.zero?
        assert_equal 0, usage.cost_estimate_cents
      else
        assert_nil usage.cost_estimate_cents
        assert_equal false, usage.retrieval["token_usage_reported"]
      end
    end
  end

  test "#call should use limited execution once after an explicit search capability rejection" do
    [
      rejection("Web search is not supported for example/future-model."),
      rejection("Unsupported tools", param: "tools", code: "unsupported_parameter"),
      rejection("Unsupported limit", param: "max_tool_calls", code: "unsupported_parameter"),
      rejection("No endpoints found that support tool use.", status: 404)
    ].each do |response|
      @context = nil
      stub_chat(response, reply)

      assert_equal "An original joke", gather.payload

      assert_equal 2, @requests.size
      assert @requests.last["tools"].all? { |tool| tool["type"] != "openrouter:web_search" }
      assert_nil @requests.last["max_tool_calls"]
      usages = LlmUsage.order(:created_at).last(2)
      assert_equal %w[provider_error success], usages.map(&:outcome)
      assert_nil usages.first.cost_estimate_cents
      assert usages.first.error_message.present?
      assert_equal "limited", usages.last.retrieval["mode"]
      assert_not usages.last.retrieval.key?("reported_cost_cents")
      assert credential.reload.active?
    end
  end

  test "#call should fall back to supplied public pages when server tools are disabled" do
    credential.update!(available_models: [{ "id" => "example/future-model", "metadata" => { "tool_call" => false } }])
    stub_chat(rejection("Server tools are disabled for your account."), reply("Supplied fact"))
    stub_request(:get, SOURCE).to_return(body: "<p>Supplied fact</p>")

    result = Socket.stub(:getaddrinfo, [["AF_INET", 0, "example.com", "93.184.216.34"]]) do
      gather("Summarize #{SOURCE}")
    end

    assert_equal "Supplied fact", result.payload
    assert_equal 2, @requests.size
    assert_nil @requests.last["tools"]
    assert_includes @requests.last["messages"].to_json, "Supplied fact"
    assert_equal "limited", LlmUsage.order(:created_at).last.retrieval["mode"]
  end

  test "#call should preserve an explicit external search selection" do
    search = create(:search_credential, :active, user: credential.user)
    @context = LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader,
                                         model: "example/future-model", search_credential: search)
    stub_chat(reply)

    assert_equal "An original joke", gather.payload

    assert_equal 2, @requests.sole["tools"].size
    assert @requests.sole["tools"].all? { |tool| tool["type"] == "function" }
    assert_nil @requests.sole["max_tool_calls"]
    assert_equal "external", LlmUsage.sole.retrieval["mode"]
    assert_not LlmUsage.sole.retrieval.key?("reported_cost_cents")
  end

  test "#call should offer hosted search with inactive external credentials regardless of client tool metadata" do
    search = create(:search_credential, :inactive, user: credential.user)
    @context = LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader,
                                         model: "example/future-model", search_credential: search)
    credential.update!(available_models: [{ "id" => "example/future-model", "metadata" => { "tool_call" => false } }])
    stub_chat(reply)

    assert_equal "An original joke", gather.payload

    assert_equal "openrouter:web_search", @requests.sole["tools"].sole["type"]
    assert_equal 8_192, @requests.sole["max_tokens"]
  end

  test "#call should share the remaining search allowance and avoid uncapped requests" do
    context.tool_budget.reserve(7)
    stub_chat(reply)

    gather

    assert_equal 1, @requests.sole["max_tool_calls"]
    assert_equal 1, @requests.sole["tools"].sole["parameters"]["max_uses"]
    assert_equal 3, @requests.sole["tools"].sole["parameters"]["max_total_results"]
    assert_equal 8, context.tool_budget.spent
  end

  test "#call should skip hosted search without a paid attempt when the shared allowance is exhausted" do
    context.tool_budget.reserve(8)
    stub_chat(reply)

    assert_equal "An original joke", gather.payload

    assert @requests.sole["tools"].all? { |tool| tool["type"] != "openrouter:web_search" }
    assert_equal "limited", LlmUsage.sole.retrieval["mode"]
  end

  test "#call should fail incomplete output and retain billed usage without an extra request" do
    [reply("Partial answer", finish: "length"), reply("Partial answer", finish: "content_filter"),
     reply("Partial answer", finish: "error"), reply("Partial answer", calls: [{ id: "unfinished" }]),
     reply({ invalid: "content" })].each do |response|
      @context = nil
      stub_chat(response)

      assert_difference -> { LlmUsage.count }, 1 do
        assert_raises(LlmClient::ProviderError) { gather }
      end
      assert_equal 1, @requests.size
      usage = LlmUsage.order(:created_at).last
      assert_equal "provider_error", usage.outcome
      assert_equal 70, usage.input_tokens
      assert_equal 2, usage.cost_estimate_cents
    end
  end

  test "#load should not turn citation metadata or private reasoning into items when the answer is blank" do
    stub_chat(reply(nil, annotations: [citation]))
    feed = build(:feed, user: credential.user, ai_credential: credential, ai_model: "example/future-model",
                        search_credential: nil, feed_profile_key: "llm", params: { "prompt" => "Find news" })

    assert_equal [], Loader::LlmLoader.new(feed).load

    assert_equal 1, @requests.size
    assert_equal 2, LlmUsage.sole.cost_estimate_cents
  end

  test "#call should ignore malformed and non-web citations without losing the answer" do
    stub_chat(reply("Available fact", annotations: [nil, "invalid", { type: "url_citation" }, citation("javascript:alert(1)")]))

    assert_equal "Available fact", gather.payload
  end

  test "#call should not retry auth rate limit server malformed tool or unknown model errors" do
    [
      [rejection("Invalid key", status: 401), LlmClient::AuthError],
      [rejection("Insufficient credits", status: 402), LlmClient::AuthError],
      [rejection("Request forbidden", status: 403), LlmClient::AuthError],
      [rejection("Too many requests", status: 429), LlmClient::RateLimited],
      [rejection("Unavailable", status: 500), LlmClient::ProviderError],
      [rejection("tools.0.parameters.max_uses: invalid value"), LlmClient::ProviderError],
      [rejection("No endpoints found for example/future-model", status: 404), LlmClient::ProviderError]
    ].each do |response, error_class|
      @context = nil
      stub_chat(response)

      assert_difference -> { LlmUsage.count }, 1 do
        assert_raises(error_class) { gather }
      end
      assert_equal 1, @requests.size
      assert_nil LlmUsage.order(:created_at).last.cost_estimate_cents
    end
  end

  test "#call should record unknown charges once on timeout" do
    stub_request(:post, ENDPOINT).to_raise(Faraday::TimeoutError.new("execution expired"))

    assert_raises(LlmClient::Timeout) { gather }

    usage = LlmUsage.sole
    assert_equal "timeout", usage.outcome
    assert_nil usage.cost_estimate_cents
    assert_equal false, usage.retrieval["token_usage_reported"]
    assert_requested :post, ENDPOINT, times: 1
  end
end
