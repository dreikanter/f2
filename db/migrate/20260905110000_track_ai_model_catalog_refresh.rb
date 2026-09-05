class TrackAiModelCatalogRefresh < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_credentials, :models_refreshed_at, :datetime
    change_column_null :llm_usages, :cost_estimate_cents, true, 0
    change_column_default :llm_usages, :cost_estimate_cents, from: 0, to: nil
  end
end
