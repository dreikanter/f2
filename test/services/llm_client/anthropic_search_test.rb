require "test_helper"

class LlmClient::AnthropicSearchTest < ActiveSupport::TestCase
  ENDPOINT = "https://api.anthropic.com/v1/messages".freeze
  SOURCE = "https://example.com/release".freeze

  def credential
    @credential ||= create(:ai_credential, :active, provider: "anthropic", credential_data: { "api_key" => "claude-test" },
                            available_models: [{ "id" => "future-claude", "metadata" => {
                              "max_output_tokens" => 1_024, "structured_output" => false,
                              "pricing" => { "input" => 1, "output" => 2, "cache_read" => 0.1, "cache_write" => 1.25 }
                            } }])
  end

  def context
    @context ||= LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader,
                                           model: "future-claude", purpose: :preview)
  end

  def gather(prompt = "Invent a joke please")
    LlmClient.new(credential).call(context, prompt: prompt, output_schema: nil,
                                 system: Loader::LlmPrompts::GATHER_SYSTEM, web: true)
  end

  def json(body, status: 200)
    { status: status, headers: { "Content-Type" => "application/json" }, body: body.to_json }
  end

  def text_block(text, citations: [])
    { type: "text", text: text, citations: citations }
  end

  def search_blocks(error: nil)
    result = if error
      { type: "web_search_tool_result_error", error_code: error }
    else
      [{ type: "web_search_result", url: SOURCE, title: "Release", encrypted_content: "opaque search evidence" }]
    end
    [
      { type: "server_tool_use", id: "search-1", name: "web_search", input: { query: "recent release" } },
      { type: "web_search_tool_result", tool_use_id: "search-1", content: result }
    ]
  end

  def reply(text = "An original joke", blocks: nil, stop: "end_turn", searches: 0, usage: true)
    body = { id: "message-1", type: "message", role: "assistant", model: "future-claude",
             content: blocks || [text_block(text)], stop_reason: stop, stop_sequence: nil }
    body[:usage] = { input_tokens: 100, output_tokens: 30, cache_read_input_tokens: 20,
                     cache_creation_input_tokens: 10, server_tool_use: { web_search_requests: searches } } if usage
    json(body)
  end

  def rejection(message, status: 400, type: "invalid_request_error")
    json({ type: "error", error: { type: type, message: message } }, status: status)
  end

  def stub_messages(*responses)
    @requests = []
    stub_request(:post, ENDPOINT).with(headers: { "X-Api-Key" => "claude-test", "Anthropic-Version" => "2023-06-01" }) do |request|
      @requests << JSON.parse(request.body)
      true
    end.to_return(*responses)
  end

  test "#call should offer bounded native search to an exact unregistered model without forcing optional parameters" do
    stub_messages(reply)

    assert_equal "An original joke", gather.payload

    request = @requests.sole
    assert_equal "future-claude", request["model"]
    assert_equal [{ "type" => "web_search_20250305", "name" => "web_search", "max_uses" => 2 }], request["tools"]
    assert_equal 1_024, request["max_tokens"]
    assert_nil request["temperature"]
    assert_nil request["thinking"]
    assert_nil request["tool_choice"]
    assert_nil request["output_config"]
    assert_includes request["system"], "create it directly"
    assert_equal "Invent a joke please", request["messages"].sole["content"]
    usage = LlmUsage.sole
    assert_equal 0, usage.retrieval["search_calls"]
    assert_equal 100, usage.input_tokens
    assert_equal 20, usage.cache_read_tokens
    assert_equal 10, usage.cache_write_tokens
    assert_not_nil usage.cost_estimate_cents
  end

  test "#execute should retain citations through separate extraction and associate all preview usage with the saved feed" do
    citation = { type: "web_search_result_location", url: SOURCE, title: "Release", cited_text: "Release facts", encrypted_index: "opaque-index" }
    stub_messages(reply(blocks: search_blocks + [text_block("Release facts", citations: [citation])], searches: 1),
                  reply('{"items":[{"body":"Release facts","source_url":"https://example.com/release"}]}'))
    feed = create(:feed, :draft, user: credential.user, ai_credential: credential, ai_model: "future-claude",
                         search_credential: nil, feed_profile_key: "llm", params: { "prompt" => "Find a recent release" })
    preview = create(:feed_preview, user: feed.user, feed: feed, ai_credential: credential, ai_model: feed.ai_model,
                                    feed_profile_key: "llm", params: feed.params)

    assert_no_difference -> { Post.count } do
      FeedPreviewWorkflow.new(preview, run_id: preview.run_id).execute
    end

    assert preview.reload.ready?
    assert_includes preview.posts_data.sole["content"], SOURCE
    assert_equal 2, @requests.size
    assert_nil @requests[1]["tools"]
    prompt = @requests[1]["messages"].to_json
    assert_includes prompt, "Citations for this passage"
    assert_includes prompt, SOURCE
    assert_not_includes prompt, "opaque-index"
    assert_not_includes prompt, "opaque search evidence"
    usages = feed.llm_usages.order(:created_at)
    event = feed.events.find_by!(type: "feed_preview")
    assert_equal 2, usages.count
    assert_equal usages.pluck(:id).sort, event.references.grep(LlmUsage).map(&:id).sort
    assert_equal ["future-claude"], usages.pluck(:model).uniq
    assert_equal 1, usages.first.retrieval["search_calls"]
    assert_nil usages.first.cost_estimate_cents
    assert_not_nil usages.last.cost_estimate_cents
  end

  test "#call should continue a paused turn unchanged and aggregate usage across both requests" do
    paused = [text_block("I will search"), { type: "thinking", thinking: "Reasoning", signature: "signed-reasoning" }] + search_blocks
    stub_messages(reply(blocks: paused, stop: "pause_turn", searches: 1), reply("Found facts", searches: 1))

    assert_equal "I will search\n\nFound facts", gather.payload

    assert_equal 2, @requests.size
    assert_equal @requests.first["tools"], @requests.last["tools"]
    assert_equal JSON.parse(paused.to_json), @requests.last["messages"].last["content"]
    assert_equal "assistant", @requests.last["messages"].last["role"]
    usage = LlmUsage.sole
    assert_equal 200, usage.input_tokens
    assert_equal 60, usage.output_tokens
    assert_equal 40, usage.cache_read_tokens
    assert_equal 20, usage.cache_write_tokens
    assert_equal 2, usage.retrieval["completion_calls"]
    assert_equal 2, usage.retrieval["search_calls"]
    assert_nil usage.cost_estimate_cents
    assert_equal 4, context.tool_budget.spent
  end

  test "#load should preserve cited partial answers before a paused search into extraction" do
    citation = { type: "web_search_result_location", url: SOURCE, title: "Release", cited_text: "First fact" }
    paused = search_blocks + [text_block("First fact", citations: [citation]), text_block("Additional detail"),
                              { type: "server_tool_use", id: "search-2", name: "web_search", input: { query: "follow-up" } }]
    continued = [{ type: "web_search_tool_result", tool_use_id: "search-2", content: [] }, text_block("Second fact")]
    stub_messages(reply(blocks: paused, stop: "pause_turn", searches: 1), reply(blocks: continued, searches: 1),
                  reply('{"items":[{"body":"First fact and second fact","source_url":"https://example.com/release"}]}'))
    feed = build(:feed, user: credential.user, ai_credential: credential, ai_model: "future-claude",
                        search_credential: nil, feed_profile_key: "llm", params: { "prompt" => "Find news" })

    assert_equal SOURCE, Loader::LlmLoader.new(feed).load.sole["source_url"]

    assert_equal 3, @requests.size
    prompt = @requests.last["messages"].to_json
    assert_includes prompt, "First fact"
    assert_includes prompt, "Additional detail"
    assert_includes prompt, "Second fact"
    assert_includes prompt, SOURCE
    assert_not_includes prompt, "opaque search evidence"
    assert_equal JSON.parse(paused.to_json), @requests[1]["messages"].last["content"]
    assert_nil @requests.last["tools"]
    assert_equal [200, 100], LlmUsage.order(:created_at).pluck(:input_tokens)
  end

  test "#call should stop a repeatedly paused turn without an unbounded continuation" do
    stub_messages(reply(blocks: search_blocks, stop: "pause_turn", searches: 1))

    assert_raises(LlmClient::ProviderError) { gather }

    assert_equal 2, @requests.size
    assert_equal 200, LlmUsage.sole.input_tokens
    assert_equal "provider_error", LlmUsage.sole.outcome
    assert_equal 2, LlmUsage.sole.retrieval["search_calls"]
  end

  test "#call should reserve only the remaining allowance and decline a continuation without enough budget" do
    context.tool_budget.reserve(7)
    stub_messages(reply(stop: "pause_turn", searches: 1))

    assert_raises(LlmClient::ProviderError) { gather }

    assert_equal 1, @requests.sole["tools"].sole["max_uses"]
    assert_equal 8, context.tool_budget.spent
    assert_equal 100, LlmUsage.sole.input_tokens
  end

  test "#call should use limited execution when the shared search allowance is already exhausted" do
    context.tool_budget.reserve(8)
    stub_messages(reply)

    assert_equal "An original joke", gather.payload

    assert @requests.sole["tools"].all? { |tool| tool["type"] != "web_search_20250305" }
    assert_equal "limited", LlmUsage.sole.retrieval["mode"]
  end

  test "#call should fall back to supplied pages when the organization disables search" do
    credential.update!(available_models: [{ "id" => "future-claude", "metadata" => { "tool_call" => false } }])
    stub_messages(rejection("Web search is not enabled for your organization."), reply("Supplied fact"))
    stub_request(:get, SOURCE).to_return(body: "<p>Supplied fact</p>")

    result = Socket.stub(:getaddrinfo, [["AF_INET", 0, "example.com", "93.184.216.34"]]) do
      gather("Summarize #{SOURCE}")
    end

    assert_equal "Supplied fact", result.payload
    assert_equal 2, @requests.size
    assert_nil @requests.last["tools"]
    assert_includes @requests.last["messages"].to_json, "Supplied fact"
    assert_equal %w[provider_error success], LlmUsage.order(:created_at).pluck(:outcome)
    assert_equal "limited", LlmUsage.order(:created_at).last.retrieval["mode"]
    assert credential.reload.active?
  end

  test "#call should fall back once for a search rejection naming the selected model" do
    stub_messages(rejection("Web search is not supported for future-claude."), reply)

    assert_equal "An original joke", gather.payload

    assert_equal 2, @requests.size
    assert @requests.last["tools"].all? { |tool| tool["type"] != "web_search_20250305" }
    assert_equal "limited", LlmUsage.order(:created_at).last.retrieval["mode"]
  end

  test "#call should retain partial native usage when a continuation rejects search before fallback" do
    stub_messages(reply(stop: "pause_turn", searches: 1), rejection("Web search is disabled."), reply)

    assert_equal "An original joke", gather.payload

    usages = LlmUsage.order(:created_at)
    assert_equal %w[provider_error success], usages.pluck(:outcome)
    assert_equal 100, usages.first.input_tokens
    assert_nil usages.first.cost_estimate_cents
    assert_equal false, usages.first.retrieval["token_usage_reported"]
    assert_equal 3, @requests.size
  end

  test "#call should retain useful limited content and report HTTP success tool errors" do
    stub_messages(reply("An original joke", blocks: search_blocks(error: "unavailable") + [text_block("An original joke")]))

    assert_equal "An original joke", gather.payload

    assert_equal 1, @requests.size
    assert_equal ["unavailable"], LlmUsage.sole.retrieval["search_statuses"]
    assert_equal 0, LlmUsage.sole.retrieval["search_calls"]
    assert_not_nil LlmUsage.sole.cost_estimate_cents
  end

  test "#load should not turn search planning or citation metadata into feed items" do
    stub_messages(reply(blocks: [text_block("I will search now")] + search_blocks + [text_block("")], searches: 1))
    feed = build(:feed, user: credential.user, ai_credential: credential, ai_model: "future-claude",
                        search_credential: nil, feed_profile_key: "llm", params: { "prompt" => "Find news" })

    assert_raises(Loader::Error) { Loader::LlmLoader.new(feed).load }
    assert_equal "schema_error", LlmUsage.sole.outcome

    assert_equal 1, @requests.size
    assert_nil LlmUsage.sole.cost_estimate_cents
  end

  test "#call should keep missing token or search usage unknown" do
    [reply(usage: false), reply(searches: nil)].each do |response|
      @context = nil
      stub_messages(response)

      result = gather

      assert_nil LlmUsage.find(result.usage_id).cost_estimate_cents
      assert_nil LlmUsage.find(result.usage_id).retrieval["search_calls"]
    end
  end

  test "#call should preserve unknown usage when a later continuation has complete usage" do
    stub_messages(reply(stop: "pause_turn", usage: false), reply)

    gather

    assert_equal 100, LlmUsage.sole.input_tokens
    assert_equal false, LlmUsage.sole.retrieval["token_usage_reported"]
    assert_nil LlmUsage.sole.cost_estimate_cents
  end

  test "#call should preserve external search selection" do
    search = create(:search_credential, :active, user: credential.user)
    @context = LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader,
                                         model: "future-claude", search_credential: search)
    stub_messages(reply)

    assert_equal "An original joke", gather.payload

    assert_equal 2, @requests.sole["tools"].size
    assert @requests.sole["tools"].all? { |tool| tool["type"] != "web_search_20250305" }
    assert_equal "external", LlmUsage.sole.retrieval["mode"]
  end

  test "#call should try native search with inactive external credentials regardless of client tool metadata" do
    search = create(:search_credential, :inactive, user: credential.user)
    @context = LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader,
                                         model: "future-claude", search_credential: search)
    credential.update!(available_models: [{ "id" => "future-claude", "metadata" => { "tool_call" => false } }])
    stub_messages(reply)

    assert_equal "An original joke", gather.payload

    assert_equal "web_search_20250305", @requests.sole["tools"].sole["type"]
  end

  test "#call should fail incomplete output and preserve billed usage" do
    %w[max_tokens refusal tool_use].each do |stop|
      @context = nil
      stub_messages(reply("Incomplete content", stop: stop, searches: 1))

      assert_difference -> { LlmUsage.count }, 1 do
        assert_raises(LlmClient::ProviderError) { gather }
      end
      assert_equal 1, @requests.size
      usage = LlmUsage.order(:created_at).last
      assert_equal 100, usage.input_tokens
      assert_equal 1, usage.retrieval["search_calls"]
      assert_nil usage.cost_estimate_cents
    end
  end

  test "#call should not retry auth rate limit server malformed tool or unknown model errors" do
    [
      [rejection("Invalid key", status: 401, type: "authentication_error"), LlmClient::AuthError],
      [rejection("Request forbidden", status: 403, type: "permission_error"), LlmClient::AuthError],
      [rejection("Too many requests", status: 429, type: "rate_limit_error"), LlmClient::RateLimited],
      [rejection("Unavailable", status: 500, type: "api_error"), LlmClient::ProviderError],
      [rejection("tools.0.max_uses: invalid value"), LlmClient::ProviderError],
      [rejection("model: future-claude", status: 404, type: "not_found_error"), LlmClient::ProviderError]
    ].each do |response, error_class|
      @context = nil
      stub_messages(response)

      assert_difference -> { LlmUsage.count }, 1 do
        assert_raises(error_class) { gather }
      end
      assert_equal 1, @requests.size
    end
  end

  test "#call should retain earlier tokens and unknown search charges after a continuation timeout" do
    request = stub_messages(reply(stop: "pause_turn", searches: 1))
    request.then.to_raise(Faraday::TimeoutError.new("execution expired"))

    assert_raises(LlmClient::Timeout) { gather }

    assert_equal 2, @requests.size
    usage = LlmUsage.sole
    assert_equal 100, usage.input_tokens
    assert_equal 30, usage.output_tokens
    assert_equal "timeout", usage.outcome
    assert_nil usage.retrieval["search_calls"]
    assert_equal false, usage.retrieval["token_usage_reported"]
    assert_nil usage.cost_estimate_cents
  end
end
