require "test_helper"

class LlmProviderTest < ActiveSupport::TestCase
  test "#all should offer implemented providers" do
    assert_equal ["openai"], LlmProvider.names
    assert_equal [LlmProvider.find("openai")], LlmProvider.all
  end

  test "#find should return the OpenAI provider" do
    provider = LlmProvider.find(:openai)

    assert_instance_of Ai::Providers::Openai, provider
    assert_equal "openai", provider.name
    assert_equal "OpenAI", provider.display_name
    assert_equal "gpt-5.6-luna", provider.default_model
  end

  test "#find should reject unknown providers" do
    assert_raises(KeyError) { LlmProvider.find("does-not-exist") }
    assert_raises(KeyError) { LlmProvider.find(nil) }
  end
end
