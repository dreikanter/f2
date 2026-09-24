require "test_helper"

class LlmProviderTest < ActiveSupport::TestCase
  test "#all should offer implemented providers" do
    assert_equal ["openai", "xai"], LlmProvider.names
    assert_equal({ "openai" => LlmProvider.find("openai"), "xai" => LlmProvider.find("xai") }, LlmProvider.all)
  end

  test "#find should return the OpenAI configuration" do
    config = LlmProvider.find(:openai)

    assert_equal LlmProvider::Openai, config.fetch(:adapter_class)
    assert_equal "OpenAI", config.fetch(:display_name)
  end

  test "#find should reject unknown providers" do
    assert_raises(KeyError) { LlmProvider.find("does-not-exist") }
    assert_raises(KeyError) { LlmProvider.find(nil) }
  end

  test "#build should use the xAI adapter and validator" do
    config = LlmProvider.find(:xai)
    provider = LlmProvider.build(:xai, credential_data: { "api_key" => "xai-test-key" })

    assert_instance_of LlmProvider::Xai, provider
    assert_equal "xai-test-key", provider.context.config.xai_api_key
    assert_equal AiCredentialValidator::Xai, config.fetch(:validator_class)
    assert_equal "xAI", config.fetch(:display_name)
  end
end
