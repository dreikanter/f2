require "test_helper"

class LlmClient::AdapterTest < ActiveSupport::TestCase
  def fake_chat
    Class.new do
      attr_reader :tools

      def initialize = @tools = []
      def with_tool(tool) = @tools << tool
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

  test "Base#web_params should raise NotImplementedError" do
    assert_raises(NotImplementedError) { LlmClient::Adapter::Base.new.web_params("any-model") }
  end

  test "anthropic #web_params should declare web search and fetch server tools" do
    types = LlmClient::Adapter::Anthropic.new.web_params("claude-opus-4-8").fetch(:tools).map { |t| t[:type] }

    assert_includes types, "web_search_20260209"
    assert_includes types, "web_fetch_20260209"
  end

  test "openrouter #web_params should enable the web plugin and require parameters" do
    params = LlmClient::Adapter::OpenRouter.new.web_params("openai/gpt-4o")

    assert_equal [{ id: "web" }], params.fetch(:plugins)
    assert params.dig(:provider, :require_parameters)
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

  test "moonshot #apply_web should register only the fetch tool when web search is unconfigured" do
    chat = fake_chat

    WebSearchProvider.stub(:configured?, false) do
      LlmClient::Adapter::Moonshot.new.apply_web(chat, "kimi-k2.5")
    end

    assert_equal [LlmClient::Tools::WebFetch], chat.tools
  end

  test "moonshot #apply_web should also register the search tool when web search is configured" do
    chat = fake_chat

    WebSearchProvider.stub(:configured?, true) do
      LlmClient::Adapter::Moonshot.new.apply_web(chat, "kimi-k2.5")
    end

    assert_equal [LlmClient::Tools::WebSearch, LlmClient::Tools::WebFetch], chat.tools
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
