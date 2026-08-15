require "test_helper"

class LlmModelCapabilityTest < ActiveSupport::TestCase
  test "#supported? should be true only for allowlisted pairs" do
    assert LlmModelCapability.supported?("anthropic", "claude-sonnet-4-6")
    assert LlmModelCapability.supported?("moonshot", "kimi-k2.6")
    assert_not LlmModelCapability.supported?("anthropic", "some-unverified-model")
    assert_not LlmModelCapability.supported?("openrouter", "anthropic/claude-sonnet-4-6")
  end

  test "#supported? should accept symbol provider keys" do
    assert LlmModelCapability.supported?(:anthropic, "claude-sonnet-4-6")
  end

  test "#models_for should list a provider's verified models and nothing for unlisted providers" do
    assert_includes LlmModelCapability.models_for("anthropic"), "claude-sonnet-4-6"
    assert_empty LlmModelCapability.models_for("openrouter")
  end

  test "every provider with matrix rows should have a supported default_model" do
    providers_with_rows = LlmModelCapability.all.map { |entry| entry[:provider] }.uniq
    providers_with_rows.each do |name|
      provider = LlmProvider.find(name)
      assert LlmModelCapability.supported?(provider.name, provider.default_model),
             "#{provider.name} default_model #{provider.default_model} must be in the capability matrix"
    end
  end

  test "matrix entries should carry a provider and model and nothing else" do
    LlmModelCapability.all.each do |entry|
      assert_equal %i[provider model], entry.keys,
                   "#{entry[:model]} carries metadata no production code reads"
    end
  end

  test "every matrix provider should be a registered LlmProvider" do
    LlmModelCapability.all.each do |entry|
      assert_includes LlmProvider.names, entry[:provider],
                      "#{entry[:provider]} is not a registered LlmProvider"
    end
  end
end
