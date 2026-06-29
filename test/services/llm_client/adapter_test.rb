require "test_helper"

class LlmClient::AdapterTest < ActiveSupport::TestCase
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
end
