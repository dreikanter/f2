require "test_helper"

class LlmProviderTest < ActiveSupport::TestCase
  test "#all should list registered provider keys" do
    assert_includes LlmProvider.all, "anthropic"
  end

  test "#exists? should return true for registered providers" do
    assert LlmProvider.exists?("anthropic")
    assert LlmProvider.exists?(:anthropic)
  end

  test "#exists? should return false for unknown providers" do
    refute LlmProvider.exists?("does-not-exist")
    refute LlmProvider.exists?(nil)
  end

  test "#[] should return the registry entry" do
    entry = LlmProvider["anthropic"]
    assert_kind_of Hash, entry
    assert_equal "Anthropic (Claude)", entry[:display_name]
    assert_equal :anthropic, entry[:ruby_llm_provider]
  end

  test "#display_name_for should return the human-readable label" do
    assert_equal "Anthropic (Claude)", LlmProvider.display_name_for("anthropic")
  end

  test "#credential_schema_for should return a JSON Schema requiring api_key" do
    schema = LlmProvider.credential_schema_for("anthropic")
    assert_equal "object", schema["type"]
    assert_includes schema["required"], "api_key"
    assert_equal false, schema["additionalProperties"]
  end

  test "#ruby_llm_provider_for should return the RubyLLM provider symbol" do
    assert_equal :anthropic, LlmProvider.ruby_llm_provider_for("anthropic")
  end

  test "registry should be frozen" do
    assert LlmProvider::PROVIDERS.frozen?
  end
end
