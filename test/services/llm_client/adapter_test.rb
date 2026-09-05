require "test_helper"

class LlmClient::AdapterTest < ActiveSupport::TestCase
  def fake_chat
    Class.new do
      attr_reader :tools, :params

      def initialize
        @tools = []
        @params = {}
      end

      def with_tool(tool) = @tools << tool
      def with_params(**params) = @params.merge!(params)
    end.new
  end

  def search_context
    credential = create(:search_credential, :active)
    refresh_event = Event.create!(type: "feed_refresh", level: :info, user: credential.user)
    { search_credential: credential, refresh_event: refresh_event }
  end

  test ".for should return the Anthropic adapter" do
    assert_instance_of LlmClient::Adapter::Anthropic, LlmClient::Adapter.for("anthropic")
  end

  test ".for should return the OpenRouter adapter" do
    assert_instance_of LlmClient::Adapter::OpenRouter, LlmClient::Adapter.for("openrouter")
  end

  test ".for should return the OpenAI adapter" do
    assert_instance_of LlmClient::Adapter::OpenAi, LlmClient::Adapter.for("openai")
  end

  test ".for should accept a symbol provider" do
    assert_instance_of LlmClient::Adapter::Anthropic, LlmClient::Adapter.for(:anthropic)
  end

  test ".for should raise for an unknown provider" do
    assert_raises(KeyError) { LlmClient::Adapter.for("nope") }
  end

  # Adapter.for raises KeyError for a provider it has no entry for, and that
  # escapes LlmClient#call's rescue list — after the provider has already
  # billed the round trip, and without writing the usage row.
  test "every registered provider should have an adapter" do
    assert_equal LlmProvider.names.sort, LlmClient::Adapter::REGISTRY.keys.sort
  end

  test "every registered adapter should inherit from Base" do
    LlmClient::Adapter::REGISTRY.each_key do |provider|
      assert_kind_of LlmClient::Adapter::Base, LlmClient::Adapter.for(provider)
    end
  end

  test "every adapter should attach the injected search provider, credential context, and client-side fetch" do
    provider = Object.new
    context = search_context

    LlmClient::Adapter::REGISTRY.each_key do |name|
      chat = fake_chat
      LlmClient::Adapter.for(name).apply_web(chat, search_provider: provider, **context)

      search_tool, fetch_tool = chat.tools
      assert_instance_of LlmClient::Tools::WebSearch, search_tool, name
      assert_same provider, search_tool.instance_variable_get(:@provider), name
      assert_same context[:search_credential], search_tool.instance_variable_get(:@credential), name
      assert_same context[:refresh_event], search_tool.instance_variable_get(:@refresh_event), name
      assert_instance_of LlmClient::Tools::WebFetch, fetch_tool, name

      budget = search_tool.instance_variable_get(:@budget)
      assert_instance_of LlmClient::ToolBudget, budget, name
      assert_same budget, fetch_tool.instance_variable_get(:@budget), name
    end
  end

  test "Anthropic should not send provider-hosted web tools" do
    adapter = LlmClient::Adapter::Anthropic.new

    assert_equal({ max_tokens: 8_192 }, adapter.params_for("claude-opus-4-8", schema: true, web: true))
  end

  test "OpenRouter should require structured parameters without enabling its web plugin" do
    params = LlmClient::Adapter::OpenRouter.new.params_for("openai/gpt-4o", schema: false, web: true)

    assert_equal({ max_tokens: 8_192, provider: { require_parameters: true } }, params)
    assert_not params.key?(:plugins)
  end

  # An OpenRouter upstream that ignores `response_format` drops it silently, so
  # the routing constraint has to travel with the schema, not with the tools.
  test "OpenRouter should require structured parameters on a schema-only call" do
    params = LlmClient::Adapter::OpenRouter.new.params_for("openai/gpt-4o", schema: true, web: false)

    assert_equal({ max_tokens: 8_192, provider: { require_parameters: true } }, params)
  end

  test "OpenAI should opt out of reasoning on tool-enabled calls" do
    adapter = LlmClient::Adapter::OpenAi.new

    assert_equal({ max_completion_tokens: 8_192, reasoning_effort: "none" }, adapter.params_for("gpt-5.6-luna", schema: false, web: true))
  end

  # Structuring keeps its reasoning: no tool is there to collide with it.
  test "OpenAI should keep reasoning on a schema-only call" do
    adapter = LlmClient::Adapter::OpenAi.new

    assert_equal({ max_completion_tokens: 8_192 }, adapter.params_for("gpt-5.6-luna", schema: true, web: false))
  end

  test "#params_for should only bound output when a call carries neither a schema nor tools" do
    LlmClient::Adapter::REGISTRY.each_key do |name|
      parameter = name == "openai" ? :max_completion_tokens : :max_tokens
      assert_equal({ parameter => 8_192 }, LlmClient::Adapter.for(name).params_for("model", schema: false, web: false), name)
    end
  end

  # with_params replaces the whole set, so a combined call sends one merged hash.
  test "#params_for should merge the schema and web params of a combined call" do
    adapter = Class.new(LlmClient::Adapter::Base) do
      def schema_params(_model) = { provider: { require_parameters: true }, response_format: "json" }
      def web_params(_model) = { provider: { sort: "latency" }, reasoning_effort: "none" }
    end.new

    assert_equal({ max_tokens: 8_192, provider: { require_parameters: true, sort: "latency" },
                   response_format: "json", reasoning_effort: "none" },
                 adapter.params_for("model", schema: true, web: true))
  end

  def rate_limit_error(body)
    RubyLLM::RateLimitError.new(Struct.new(:body).new(body), "429")
  end

  test "#dead_key? should be false where a 429 only ever means throttling" do
    assert_not LlmClient::Adapter::Base.new.dead_key?(rate_limit_error(""))
    assert_not LlmClient::Adapter::Anthropic.new.dead_key?(
      rate_limit_error({ error: { type: "insufficient_quota" } }.to_json)
    )
  end

  test "#dead_key? should cover every billing stop OpenAI reports as a 429" do
    adapter = LlmClient::Adapter::OpenAi.new

    LlmClient::Adapter::OpenAi::SPENT_KEY_CODES.each do |code|
      assert adapter.dead_key?(rate_limit_error({ error: { code: code } }.to_json)),
             "#{code} should read as a spent key"
    end
  end

  # The machine-readable name arrives under `code` for some failures and `type`
  # for others, so neither field can be preferred over the other.
  test "#dead_key? should read the identifier from either body field" do
    adapter = LlmClient::Adapter::OpenAi.new

    assert adapter.dead_key?(
      rate_limit_error({ error: { type: "rate_limit_error", code: "project_spend_limit_exceeded" } }.to_json)
    )
    assert LlmClient::Adapter::Moonshot.new.dead_key?(
      rate_limit_error({ error: { type: "exceeded_current_quota_error" } }.to_json)
    )
  end

  test "#dead_key? should be false for a throttling 429 from the same provider" do
    adapter = LlmClient::Adapter::OpenAi.new

    assert_not adapter.dead_key?(rate_limit_error({ error: { type: "rate_limit_exceeded" } }.to_json))
    assert_not adapter.dead_key?(rate_limit_error("<html>502</html>"))
    assert_not adapter.dead_key?(RubyLLM::RateLimitError.new("429"))
  end

  def schema_error(detail)
    RubyLLM::BadRequestError.new(Struct.new(:body).new({ error: detail }.to_json), detail[:message])
  end

  test "#unsupported_schema? should recognize explicit OpenAI schema feature rejections" do
    errors = [
      schema_error(param: "response_format", code: "unsupported_parameter", message: "Unsupported parameter"),
      schema_error(param: "response_format", code: nil,
                   message: "Invalid parameter: 'response_format' of type 'json_schema' is not supported with this model.")
    ]

    %w[openai moonshot openrouter].each do |provider|
      errors.each { |error| assert LlmClient::Adapter.for(provider).unsupported_schema?(error), provider }
    end
  end

  test "#unsupported_schema? should distinguish Anthropic feature rejection from invalid schemas" do
    adapter = LlmClient::Adapter::Anthropic.new

    assert adapter.unsupported_schema?(schema_error(message: "output_config.format is not supported for this model"))
    assert_not adapter.unsupported_schema?(schema_error(message: "output_config.format.schema: unsupported keyword oneOf"))
    assert_not adapter.unsupported_schema?(schema_error(message: "tools are not supported for this model"))
  end

  test "#unsupported_schema? should keep ambiguous and malformed errors as failures" do
    adapter = LlmClient::Adapter::OpenAi.new
    [
      RubyLLM::BadRequestError.new("response_format failed"),
      RubyLLM::BadRequestError.new(Struct.new(:body).new("not JSON")),
      schema_error(param: "response_format.json_schema.schema", code: "unsupported_parameter"),
      schema_error(param: "response_format", code: "invalid_json_schema", message: "Invalid schema"),
      schema_error(param: "response_format", code: nil, message: "Some schema keywords are not supported")
    ].each do |error|
      assert_not adapter.unsupported_schema?(error)
    end
  end

  test "#combined_extraction? should be true only for providers verified for one-call web+schema" do
    assert LlmClient::Adapter::Anthropic.new.combined_extraction?
    assert LlmClient::Adapter::OpenAi.new.combined_extraction?
    assert_not LlmClient::Adapter::OpenRouter.new.combined_extraction?
    assert_not LlmClient::Adapter::Base.new.combined_extraction?
    assert_not LlmClient::Adapter::Moonshot.new.combined_extraction?
  end

  test ".for should resolve the moonshot adapter" do
    assert_instance_of LlmClient::Adapter::Moonshot, LlmClient::Adapter.for("moonshot")
  end

  test "#schema_payload should carry strictness rather than leave it to the runtime default" do
    payload = LlmClient::Adapter::Anthropic.new.schema_payload({ "type" => "object" })

    assert_equal({ "schema" => { "type" => "object" }, "strict" => true }, payload)
  end

  test "#schema_strict? should be false only where strict mode cannot express the output schema" do
    assert LlmClient::Adapter::Base.new.schema_strict?
    assert LlmClient::Adapter::Anthropic.new.schema_strict?
    assert LlmClient::Adapter::OpenRouter.new.schema_strict?
    assert LlmClient::Adapter::Moonshot.new.schema_strict?
    assert_not LlmClient::Adapter::OpenAi.new.schema_strict?
  end

  test "openai #schema_payload should turn strictness off" do
    payload = LlmClient::Adapter::OpenAi.new.schema_payload(FeedProfile::UNIVERSAL_OUTPUT_SCHEMA)

    assert_equal FeedProfile::UNIVERSAL_OUTPUT_SCHEMA, payload["schema"]
    assert_equal false, payload["strict"]
  end

  # OpenAI rejects a strict schema whose properties are not all required, and
  # the universal schema's are not — so this is the shape that would break.
  test "the universal output schema should leave properties out of required" do
    item = FeedProfile::UNIVERSAL_OUTPUT_SCHEMA.dig("properties", "items", "items")

    assert_operator item["properties"].keys.size, :>, item["required"].size
  end

  test "openai #unwrap_json should pass provider JSON through untouched" do
    adapter = LlmClient::Adapter::OpenAi.new

    assert_equal '{"a":1}', adapter.unwrap_json('{"a":1}')
    assert_equal "```\n{\"a\":1}\n```", adapter.unwrap_json("```\n{\"a\":1}\n```")
  end

  test "moonshot #unwrap_json should strip markdown fences and pass clean JSON through" do
    adapter = LlmClient::Adapter::Moonshot.new
    assert_equal '{"items":[]}', adapter.unwrap_json("```json\n{\"items\":[]}\n```")
    assert_equal '{"a":1}', adapter.unwrap_json("```\n{\"a\":1}\n```")
    assert_equal '{"a":1}', adapter.unwrap_json('{"a":1}')
    assert_equal '{"a":1}', adapter.unwrap_json("  {\"a\":1}  ")
  end

  # Kimi drops the fence but keeps the preamble often enough to matter.
  test "moonshot #unwrap_json should recover JSON introduced by unfenced prose" do
    adapter = LlmClient::Adapter::Moonshot.new

    assert_equal '{"a":1}', adapter.unwrap_json(%(Here is the JSON:\n{"a":1}))
    assert_equal '[{"a":1}]', adapter.unwrap_json(%(Sure! [{"a":1}] — let me know.))
  end

  # Preamble prose is unrestricted, so a bracket can turn up before the payload.
  test "moonshot #unwrap_json should skip a bracket in the preamble to reach the payload" do
    adapter = LlmClient::Adapter::Moonshot.new

    assert_equal '{"items":[]}', adapter.unwrap_json(%(Response [JSON]: {"items":[]}))
    assert_equal '{"a":1}', adapter.unwrap_json(%(Result [note: 2 items]: {"a":1}))
  end

  # Prose with no JSON stays intact, so it fails as the parse error it is.
  test "moonshot #unwrap_json should leave text holding no JSON alone" do
    adapter = LlmClient::Adapter::Moonshot.new

    assert_equal "I cannot browse the web.", adapter.unwrap_json("I cannot browse the web.")
    assert_equal "no close {here", adapter.unwrap_json("no close {here")
  end

  test "moonshot #unwrap_json should tolerate prose around the fence and an uppercase tag" do
    adapter = LlmClient::Adapter::Moonshot.new

    assert_equal '{"a":1}', adapter.unwrap_json("Here you go:\n```json\n{\"a\":1}\n```\nHope that helps.")
    assert_equal '{"a":1}', adapter.unwrap_json("```JSON\n{\"a\":1}\n```")
  end

  # A gathered post can quote a code block, so a fence inside the payload is
  # content. Unwrapping it as if it were the wrapper corrupts valid JSON.
  test "moonshot #unwrap_json should leave a fence quoted inside the payload alone" do
    adapter = LlmClient::Adapter::Moonshot.new
    payload = %q({"items":[{"body":"install it: ```ruby\ngem \"foo\"\n``` done"}]})

    assert_equal payload, adapter.unwrap_json(payload)
    assert_equal payload, adapter.unwrap_json("```json\n#{payload}\n```")
    assert JSON.parse(adapter.unwrap_json("```json\n#{payload}\n```"))
  end

  test "moonshot #unwrap_json should pass a bare JSON array through" do
    assert_equal '[{"a":1}]', LlmClient::Adapter::Moonshot.new.unwrap_json('[{"a":1}]')
  end

  test "base #unwrap_json should be identity" do
    assert_equal "```json\n{}\n```", LlmClient::Adapter::Base.new.unwrap_json("```json\n{}\n```")
  end
end
