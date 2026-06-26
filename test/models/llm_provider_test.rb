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

  test "every provider should declare a default_model with a known rate" do
    LlmProvider.all.each do |provider|
      assert provider.default_model.present?, "#{provider.name} must declare a default_model"
      assert LlmClient::RateTable.rate_for(provider: provider.name, model: provider.default_model),
             "#{provider.name} default_model #{provider.default_model} must have a rate entry"
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
