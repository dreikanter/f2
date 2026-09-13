class SimplifyProviderCredentialState < ActiveRecord::Migration[8.2]
  def change
    [:ai_credentials, :search_credentials].each do |table|
      remove_index table, [:user_id, :state]
      remove_column table, :state, :integer, default: 0, null: false
      add_column table, :active, :boolean, default: false, null: false
      add_index table, [:user_id, :active]
    end
  end
end
