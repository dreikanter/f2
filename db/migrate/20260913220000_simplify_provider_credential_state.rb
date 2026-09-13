class SimplifyProviderCredentialState < ActiveRecord::Migration[8.2]
  def change
    remove_index :ai_credentials, [:user_id, :state]
    remove_column :ai_credentials, :state, :integer, default: 0, null: false
    add_column :ai_credentials, :active, :boolean, default: false, null: false
    add_index :ai_credentials, [:user_id, :active]

    remove_index :search_credentials, [:user_id, :state]
    remove_column :search_credentials, :state, :integer, default: 0, null: false
    add_column :search_credentials, :active, :boolean, default: false, null: false
    add_index :search_credentials, [:user_id, :active]
  end
end
