require "test_helper"
require_relative "../../db/migrate/20260906140000_preserve_fractional_llm_costs"

class FractionalLlmCostsMigrationTest < ActiveSupport::TestCase
  test "#up should preserve historical and unknown costs through rollback and reapplication" do
    original = [nil, 0, 25, 2_147_483_647]
    usages = original.map { |cost| create(:llm_usage, cost_estimate_cents: cost) }
    fractional = ["0.4", "0.6"].map { |cost| create(:llm_usage, cost_estimate_cents: cost) }
    migration = PreserveFractionalLlmCosts.new

    migration.migrate(:down)
    LlmUsage.reset_column_information
    assert_equal :integer, LlmUsage.columns_hash.fetch("cost_estimate_cents").type
    assert_equal original, usages.map { |usage| usage.reload.cost_estimate_cents }
    assert_equal [0, 1], fractional.map { |usage| usage.reload.cost_estimate_cents }

    migration.migrate(:up)
    LlmUsage.reset_column_information
    column = LlmUsage.columns_hash.fetch("cost_estimate_cents")
    assert_equal :decimal, column.type
    assert_equal 20, column.precision
    assert_equal 10, column.scale
    assert column.null
    assert_nil column.default
    assert_equal original, usages.map { |usage| usage.reload.cost_estimate_cents }
    fractional.first.reload.update!(cost_estimate_cents: "0.0000000001")
    assert_equal "0.0000000001".to_d, fractional.first.reload.cost_estimate_cents
  ensure
    LlmUsage.reset_column_information
  end
end
