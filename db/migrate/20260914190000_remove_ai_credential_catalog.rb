class RemoveAiCredentialCatalog < ActiveRecord::Migration[8.2]
  def change
    remove_column :ai_credentials, :available_models, :jsonb, default: [], null: false
    remove_column :ai_credentials, :models_refreshed_at, :datetime
  end
end
