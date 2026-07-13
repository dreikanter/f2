require "test_helper"

class CredentialNameGeneratorTest < ActiveSupport::TestCase
  ALL_COMBINATIONS = CredentialNameGenerator::ADJECTIVES.flat_map { |adj|
    CredentialNameGenerator::NOUNS.map { |noun| "anthropic #{adj} #{noun}" }
  }.to_set.freeze

  test "#generate should fall back to numeric suffix when all word combinations are taken" do
    result = CredentialNameGenerator.new("anthropic", ALL_COMBINATIONS).generate
    assert_equal "anthropic 1", result
  end

  test "#generate should increment the numeric suffix when lower numbers are also taken" do
    existing = ALL_COMBINATIONS | Set["anthropic 1", "anthropic 2"]
    result = CredentialNameGenerator.new("anthropic", existing).generate
    assert_equal "anthropic 3", result
  end
end
