class AddAvailableModelsToAiCredentials < ActiveRecord::Migration[8.2]
  def change
    add_column :ai_credentials, :available_models, :jsonb, null: false, default: []
  end
end
