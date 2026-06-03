require "test_helper"

class LlmCredential::NameGeneratorTest < ActiveSupport::TestCase
  ALL_COMBINATIONS = LlmCredential::NameGenerator::ADJECTIVES.flat_map { |adj|
    LlmCredential::NameGenerator::NOUNS.map { |noun| "anthropic #{adj} #{noun}" }
  }.to_set.freeze

  test "#generate should fall back to numeric suffix when all word combinations are taken" do
    result = LlmCredential::NameGenerator.new("anthropic", ALL_COMBINATIONS).generate
    assert_equal "anthropic 1", result
  end

  test "#generate should increment the numeric suffix when lower numbers are also taken" do
    existing = ALL_COMBINATIONS | Set["anthropic 1", "anthropic 2"]
    result = LlmCredential::NameGenerator.new("anthropic", existing).generate
    assert_equal "anthropic 3", result
  end
end
