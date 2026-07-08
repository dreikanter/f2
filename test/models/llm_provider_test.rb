require "test_helper"

class LlmProviderTest < ActiveSupport::TestCase
  test "#all should return registered provider instances" do
    assert_includes LlmProvider.all.map(&:name), "anthropic"
    assert_includes LlmProvider.all.map(&:name), "openrouter"
    assert LlmProvider.all.all? { |p| p.is_a?(LlmProvider) }
  end

  test "#names should list registered provider keys" do
    assert_includes LlmProvider.names, "anthropic"
    assert_includes LlmProvider.names, "openrouter"
  end

  test "#exists? should return true for registered providers" do
    assert LlmProvider.exists?("anthropic")
    assert LlmProvider.exists?(:anthropic)
    assert LlmProvider.exists?("openrouter")
    assert LlmProvider.exists?(:openrouter)
  end

  test "#exists? should return false for unknown providers" do
    refute LlmProvider.exists?("does-not-exist")
    refute LlmProvider.exists?(nil)
  end

  test "#find should return the anthropic provider instance" do
    provider = LlmProvider.find("anthropic")
    assert_kind_of LlmProvider, provider
    assert_equal "anthropic", provider.name
    assert_equal "Anthropic", provider.display_name
    assert_equal :anthropic, provider.ruby_llm_provider
    assert_equal "claude-sonnet-4-6", provider.default_model
  end

  test "#find should return the openrouter provider instance" do
    provider = LlmProvider.find("openrouter")
    assert_kind_of LlmProvider, provider
    assert_equal "openrouter", provider.name
    assert_equal "OpenRouter", provider.display_name
    assert_equal :openrouter, provider.ruby_llm_provider
    assert_equal "anthropic/claude-sonnet-4-6", provider.default_model
  end

  test "#find should return the moonshot provider mapped to the openai runtime" do
    provider = LlmProvider.find("moonshot")
    assert_equal "moonshot", provider.name
    assert_equal :openai, provider.ruby_llm_provider
    assert_equal "kimi-k2.5", provider.default_model
    assert_equal "https://api.moonshot.ai/v1", provider.api_base
    assert provider.assume_model_exists?
  end

  test "#assume_model_exists? should default to false for native providers" do
    assert_not LlmProvider.find("anthropic").assume_model_exists?
    assert_not LlmProvider.find("openrouter").assume_model_exists?
  end

  test "#configure should set the api key on the ruby_llm-provider key" do
    config = Struct.new(:anthropic_api_key).new
    LlmProvider.find("anthropic").configure(config, "sk-ant-x")
    assert_equal "sk-ant-x", config.anthropic_api_key
  end

  test "#configure should set the openai key and base for moonshot" do
    config = Struct.new(:openai_api_key, :openai_api_base).new
    LlmProvider.find("moonshot").configure(config, "sk-moon-x")
    assert_equal "sk-moon-x", config.openai_api_key
    assert_equal "https://api.moonshot.ai/v1", config.openai_api_base
  end

  test "every provider should declare a default_model with a known rate" do
    LlmProvider.all.each do |provider|
      assert provider.default_model.present?, "#{provider.name} must declare a default_model"
      assert LlmClient::RateTable.rate_for(provider: provider.name, model: provider.default_model),
             "#{provider.name} default_model #{provider.default_model} must have a rate entry"
    end
  end

  test "every provider's ruby_llm_provider should resolve to a registered RubyLLM provider" do
    LlmProvider.all.each do |provider|
      assert_not_nil RubyLLM::Provider.resolve(provider.ruby_llm_provider),
                     "#{provider.name} maps to unknown RubyLLM provider #{provider.ruby_llm_provider}"
    end
  end

  test "#find should accept symbol keys" do
    assert_equal "anthropic", LlmProvider.find(:anthropic).name
    assert_equal "openrouter", LlmProvider.find(:openrouter).name
  end

  test "#find should raise KeyError for unknown providers" do
    assert_raises(KeyError) { LlmProvider.find("does-not-exist") }
    assert_raises(KeyError) { LlmProvider.find(nil) }
  end

  test "instances should be frozen" do
    assert LlmProvider.find("anthropic").frozen?
    assert LlmProvider.find("openrouter").frozen?
  end

  test "registry should be frozen" do
    assert LlmProvider::PROVIDERS.frozen?
  end
end
