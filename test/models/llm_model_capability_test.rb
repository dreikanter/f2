require "test_helper"

class LlmModelCapabilityTest < ActiveSupport::TestCase
  test "#supported? should be true for a curated pair" do
    assert LlmModelCapability.supported?("anthropic", "claude-sonnet-4-6")
  end

  test "#supported? should be false for an unknown pair" do
    assert_not LlmModelCapability.supported?("anthropic", "made-up-model")
    assert_not LlmModelCapability.supported?("nope", "claude-sonnet-4-6")
  end

  test "#supported? should accept symbol providers" do
    assert LlmModelCapability.supported?(:anthropic, "claude-sonnet-4-6")
  end

  test "#capabilities_for should return the pair's capabilities" do
    capabilities = LlmModelCapability.capabilities_for("anthropic", "claude-opus-4-8")

    assert_includes capabilities, LlmModelCapability::STRUCTURED_OUTPUT
    assert_includes capabilities, LlmModelCapability::WEB_SEARCH
    assert_includes capabilities, LlmModelCapability::WEB_FETCH
  end

  test "#capabilities_for should return an empty array for an unknown pair" do
    assert_empty LlmModelCapability.capabilities_for("anthropic", "made-up-model")
  end

  test "#capable? should reflect a single capability" do
    assert LlmModelCapability.capable?("anthropic", "claude-sonnet-4-6", LlmModelCapability::WEB_FETCH)
    assert_not LlmModelCapability.capable?("openrouter", "anthropic/claude-sonnet-4-6", LlmModelCapability::WEB_FETCH)
  end

  test "#meets? should require every listed capability" do
    assert LlmModelCapability.meets?("anthropic", "claude-sonnet-4-6", [LlmModelCapability::STRUCTURED_OUTPUT])
    assert_not LlmModelCapability.meets?(
      "openrouter", "anthropic/claude-sonnet-4-6",
      [LlmModelCapability::STRUCTURED_OUTPUT, LlmModelCapability::WEB_FETCH]
    )
  end

  test "#qualified_for_ai_feed? should be true when the required set is met" do
    assert LlmModelCapability.qualified_for_ai_feed?("openrouter", "anthropic/claude-sonnet-4-6")
  end

  test "#qualified_for_ai_feed? should be false for an unknown pair" do
    assert_not LlmModelCapability.qualified_for_ai_feed?("anthropic", "made-up-model")
  end

  test "#models_for should return only that provider's entries" do
    entries = LlmModelCapability.models_for("anthropic")

    assert entries.any?
    assert(entries.all? { |entry| entry.provider == "anthropic" })
  end

  test "#qualified_models_for should return entries meeting the required set" do
    entries = LlmModelCapability.qualified_models_for("openrouter")

    assert entries.any?
    assert(entries.all? { |entry| LlmModelCapability.qualified_for_ai_feed?(entry.provider, entry.model) })
  end

  test "#tier_for should return the reliability tier" do
    assert_equal :native, LlmModelCapability.tier_for("anthropic", "claude-opus-4-8")
    assert_equal :validated, LlmModelCapability.tier_for("openrouter", "anthropic/claude-sonnet-4-6")
    assert_nil LlmModelCapability.tier_for("anthropic", "made-up-model")
  end

  test "every curated provider should be a known LlmProvider" do
    providers = LlmModelCapability.all.map(&:provider).uniq

    providers.each { |provider| assert LlmProvider.exists?(provider), "#{provider} is not a known LlmProvider" }
  end

  test "every curated entry should qualify for an AI feed" do
    LlmModelCapability.all.each do |entry|
      assert LlmModelCapability.qualified_for_ai_feed?(entry.provider, entry.model),
             "#{entry.provider}/#{entry.model} does not meet REQUIRED_FOR_AI_FEED"
    end
  end
end
