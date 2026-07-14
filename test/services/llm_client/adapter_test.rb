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

  test ".for should return the Anthropic adapter" do
    assert_instance_of LlmClient::Adapter::Anthropic, LlmClient::Adapter.for("anthropic")
  end

  test ".for should return the OpenRouter adapter" do
    assert_instance_of LlmClient::Adapter::OpenRouter, LlmClient::Adapter.for("openrouter")
  end

  test ".for should accept a symbol provider" do
    assert_instance_of LlmClient::Adapter::Anthropic, LlmClient::Adapter.for(:anthropic)
  end

  test ".for should raise for an unknown provider" do
    assert_raises(KeyError) { LlmClient::Adapter.for("nope") }
  end

  test "every registered adapter should inherit from Base" do
    LlmClient::Adapter::REGISTRY.each_key do |provider|
      assert_kind_of LlmClient::Adapter::Base, LlmClient::Adapter.for(provider)
    end
  end

  test "every adapter should attach the injected search provider and client-side fetch" do
    provider = Object.new

    LlmClient::Adapter::REGISTRY.each_key do |name|
      chat = fake_chat
      LlmClient::Adapter.for(name).apply_web(chat, "model", search_provider: provider)

      search_tool, fetch_tool = chat.tools
      assert_instance_of LlmClient::Tools::WebSearch, search_tool, name
      assert_same provider, search_tool.instance_variable_get(:@provider), name
      assert_equal LlmClient::Tools::WebFetch, fetch_tool, name
    end
  end

  test "Anthropic should not send provider-hosted web tools" do
    chat = fake_chat

    LlmClient::Adapter::Anthropic.new.apply_web(chat, "claude-opus-4-8", search_provider: Object.new)

    assert_equal({}, chat.params)
  end

  test "OpenRouter should require structured parameters without enabling its web plugin" do
    chat = fake_chat

    LlmClient::Adapter::OpenRouter.new.apply_web(chat, "openai/gpt-4o", search_provider: Object.new)

    assert_equal({ provider: { require_parameters: true } }, chat.params)
    assert_not chat.params.key?(:plugins)
  end

  test "#combined_extraction? should be true only for providers verified for one-call web+schema" do
    assert LlmClient::Adapter::Anthropic.new.combined_extraction?
    assert_not LlmClient::Adapter::OpenRouter.new.combined_extraction?
    assert_not LlmClient::Adapter::Base.new.combined_extraction?
    assert_not LlmClient::Adapter::Moonshot.new.combined_extraction?
  end

  test ".for should resolve the moonshot adapter" do
    assert_instance_of LlmClient::Adapter::Moonshot, LlmClient::Adapter.for("moonshot")
  end

  test "moonshot #unwrap_json should strip markdown fences and pass clean JSON through" do
    adapter = LlmClient::Adapter::Moonshot.new
    assert_equal '{"items":[]}', adapter.unwrap_json("```json\n{\"items\":[]}\n```")
    assert_equal '{"a":1}', adapter.unwrap_json("```\n{\"a\":1}\n```")
    assert_equal '{"a":1}', adapter.unwrap_json('{"a":1}')
    assert_equal '{"a":1}', adapter.unwrap_json("  {\"a\":1}  ")
  end

  test "base #unwrap_json should be identity" do
    assert_equal "```json\n{}\n```", LlmClient::Adapter::Base.new.unwrap_json("```json\n{}\n```")
  end
end
