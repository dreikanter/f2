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
      LlmClient::Adapter.for(name).apply_web(chat, "model", search_provider: provider, **context)

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
    chat = fake_chat

    LlmClient::Adapter::Anthropic.new.apply_web(
      chat,
      "claude-opus-4-8",
      search_provider: Object.new,
      **search_context
    )

    assert_equal({}, chat.params)
  end

  test "OpenRouter should require structured parameters without enabling its web plugin" do
    chat = fake_chat

    LlmClient::Adapter::OpenRouter.new.apply_web(
      chat,
      "openai/gpt-4o",
      search_provider: Object.new,
      **search_context
    )

    assert_equal({ provider: { require_parameters: true } }, chat.params)
    assert_not chat.params.key?(:plugins)
  end

  test "OpenAI should opt out of reasoning on tool-enabled calls" do
    chat = fake_chat

    LlmClient::Adapter::OpenAi.new.apply_web(
      chat,
      "gpt-5.6-luna",
      search_provider: Object.new,
      **search_context
    )

    assert_equal({ reasoning_effort: "none" }, chat.params)
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
