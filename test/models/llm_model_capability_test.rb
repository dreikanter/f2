require "test_helper"

class LlmModelCapabilityTest < ActiveSupport::TestCase
  test "#supported? should be true only for allowlisted pairs" do
    assert LlmModelCapability.supported?("anthropic", "claude-sonnet-4-6")
    assert LlmModelCapability.supported?("moonshot", "kimi-k2.5")
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

  test "#capabilities_for should reflect plan-03 verification (Kimi has no server search)" do
    assert_equal %i[fetch search structured], LlmModelCapability.capabilities_for("anthropic", "claude-sonnet-4-6")
    assert_equal %i[fetch structured], LlmModelCapability.capabilities_for("moonshot", "kimi-k2.5")
    assert_not_includes LlmModelCapability.capabilities_for("moonshot", "kimi-k2.5"), :search
  end

  test "every provider with matrix rows should have a supported default_model" do
    providers_with_rows = LlmModelCapability.all.map { |entry| entry[:provider] }.uniq
    providers_with_rows.each do |name|
      provider = LlmProvider.find(name)
      assert LlmModelCapability.supported?(provider.name, provider.default_model),
             "#{provider.name} default_model #{provider.default_model} must be in the capability matrix"
    end
  end

  test "matrix entries should only use known capability symbols" do
    LlmModelCapability.all.each do |entry|
      assert (entry[:capabilities] - LlmModelCapability::CAPABILITIES).empty?,
             "#{entry[:model]} declares an unknown capability"
    end
  end

  test "every matrix provider should be a registered LlmProvider" do
    LlmModelCapability.all.each do |entry|
      assert_includes LlmProvider.names, entry[:provider],
                      "#{entry[:provider]} is not a registered LlmProvider"
    end
  end
end
