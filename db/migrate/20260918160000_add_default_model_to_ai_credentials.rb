class AddDefaultModelToAiCredentials < ActiveRecord::Migration[8.2]
  def change
    add_column :ai_credentials, :default_model, :string
  end
end
