require "test_helper"

class LlmModelCapabilityTest < ActiveSupport::TestCase
  test "#find should return the entry for a curated pair" do
    entry = LlmModelCapability.find("anthropic", "claude-sonnet-4-6")

    assert_equal "anthropic", entry.provider
    assert_equal "claude-sonnet-4-6", entry.model
    assert_equal :native, entry.tier
  end

  test "#find should accept symbol providers" do
    assert LlmModelCapability.find(:anthropic, "claude-sonnet-4-6")
  end

  test "#find should return nil for an unknown pair" do
    assert_nil LlmModelCapability.find("anthropic", "made-up-model")
    assert_nil LlmModelCapability.find("nope", "claude-sonnet-4-6")
  end

  test "#supported? should be true for a curated pair" do
    assert LlmModelCapability.supported?("anthropic", "claude-opus-4-8")
  end

  test "#supported? should be false for an unknown pair" do
    assert_not LlmModelCapability.supported?("anthropic", "made-up-model")
    assert_not LlmModelCapability.supported?("nope", "claude-opus-4-8")
  end

  test "#supported? should include the cheap Haiku option via OpenRouter" do
    assert LlmModelCapability.supported?("openrouter", "anthropic/claude-haiku-4-5")
  end

  test "#tier_for should return the reliability tier" do
    assert_equal :native, LlmModelCapability.tier_for("anthropic", "claude-opus-4-8")
    assert_equal :validated, LlmModelCapability.tier_for("openrouter", "anthropic/claude-sonnet-4-6")
    assert_nil LlmModelCapability.tier_for("anthropic", "made-up-model")
  end

  test "#models_for should return only that provider's entries" do
    entries = LlmModelCapability.models_for("anthropic")

    assert entries.any?
    assert(entries.all? { |entry| entry.provider == "anthropic" })
  end

  test "every curated provider should be a known LlmProvider" do
    providers = LlmModelCapability.all.map(&:provider).uniq

    providers.each { |provider| assert LlmProvider.exists?(provider), "#{provider} is not a known LlmProvider" }
  end

  test "every curated entry should carry a known tier" do
    LlmModelCapability.all.each do |entry|
      assert_includes LlmModelCapability::TIERS, entry.tier,
                      "#{entry.provider}/#{entry.model} has unknown tier #{entry.tier}"
    end
  end
end
