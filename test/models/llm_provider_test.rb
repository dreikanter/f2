require "test_helper"

class LlmProviderTest < ActiveSupport::TestCase
  test "#available should offer only implemented providers" do
    assert_equal ["openai"], LlmProvider.available.map(&:name)
    assert_instance_of Ai::Providers::Openai, LlmProvider.available.first.implementation
  end

  test "#find should retain saved provider identities and defaults" do
    provider = LlmProvider.find("anthropic")

    assert_equal "Anthropic", provider.display_name
    assert_equal "claude-sonnet-4-6", provider.default_model
    assert_nil provider.implementation
    assert_includes LlmProvider.names, "anthropic"
    assert_equal "OpenRouter", LlmProvider.find("openrouter").display_name
    assert_equal "Moonshot (Kimi)", LlmProvider.find("moonshot").display_name
  end

  test "#find should return OpenAI with its implementation" do
    provider = LlmProvider.find(:openai)

    assert_equal "OpenAI", provider.display_name
    assert_equal "gpt-5.6-luna", provider.default_model
    assert_instance_of Ai::Providers::Openai, provider.implementation
  end

  test "#find should reject unknown providers" do
    assert_raises(KeyError) { LlmProvider.find("does-not-exist") }
    assert_raises(KeyError) { LlmProvider.find(nil) }
  end
end
