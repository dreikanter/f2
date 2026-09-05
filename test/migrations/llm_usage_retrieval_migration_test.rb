require "test_helper"
require_relative "../../db/migrate/20260905140000_add_retrieval_to_llm_usages"

class LlmUsageRetrievalMigrationTest < ActiveSupport::TestCase
  test "#change should roll back and reapply without removing usage records" do
    usage = create(:llm_usage, retrieval: { "mode" => "native", "search_calls" => 1 }, cost_estimate_cents: nil)
    migration = AddRetrievalToLlmUsages.new
    migration.migrate(:down)
    assert_not LlmUsage.connection.column_exists?(:llm_usages, :retrieval)
    migration.migrate(:up)
    LlmUsage.reset_column_information
    assert_equal({}, usage.reload.retrieval)
    assert_nil usage.cost_estimate_cents
  ensure
    LlmUsage.reset_column_information
  end
end
