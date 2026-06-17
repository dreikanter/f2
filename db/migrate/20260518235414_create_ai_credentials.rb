class CreateAiCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_credentials do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :provider, null: false
      t.string :display_name, null: false
      t.jsonb :credential_data, null: false, default: {}
      t.boolean :is_default, null: false, default: false
      t.integer :state, null: false, default: 0
      t.datetime :last_validated_at
      t.text :last_error

      t.timestamps
    end

    add_index :ai_credentials, [:user_id, :provider, :display_name], unique: true
    add_index :ai_credentials, [:user_id, :provider],
              unique: true,
              where: "is_default = TRUE",
              name: "index_ai_credentials_on_user_provider_default"
    add_index :ai_credentials, [:user_id, :state]
  end
end
