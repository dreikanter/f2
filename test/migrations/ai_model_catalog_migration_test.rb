require "test_helper"
require_relative "../../db/migrate/20260905110000_track_ai_model_catalog_refresh"

class AiModelCatalogMigrationTest < ActiveSupport::TestCase
  test "#change should support rollback with unknown costs and reapplication" do
    usage = create(:llm_usage, cost_estimate_cents: nil)
    migration = TrackAiModelCatalogRefresh.new
    migration.migrate(:down)
    assert_not AiCredential.connection.column_exists?(:ai_credentials, :models_refreshed_at)
    assert_equal 0, usage.reload.cost_estimate_cents
    migration.migrate(:up)
    AiCredential.reset_column_information
    LlmUsage.reset_column_information
    assert AiCredential.connection.column_exists?(:ai_credentials, :models_refreshed_at)
    usage.update!(cost_estimate_cents: nil)
    assert_nil usage.reload.cost_estimate_cents
    assert_nil LlmUsage.columns_hash.fetch("cost_estimate_cents").default
  ensure
    AiCredential.reset_column_information
    LlmUsage.reset_column_information
  end
end
