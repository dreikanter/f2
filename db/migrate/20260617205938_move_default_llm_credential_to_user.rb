class MoveDefaultLlmCredentialToUser < ActiveRecord::Migration[8.2]
  def up
    add_reference :users, :default_ai_credential,
                  foreign_key: { to_table: :ai_credentials, on_delete: :nullify },
                  null: true

    # Migrate data: for each user pick the first is_default credential (any provider)
    execute <<~SQL
      UPDATE users
      SET default_ai_credential_id = (
        SELECT id FROM ai_credentials
        WHERE ai_credentials.user_id = users.id AND is_default = TRUE
        ORDER BY id ASC
        LIMIT 1
      )
    SQL

    remove_index :ai_credentials, name: "index_ai_credentials_on_user_provider_default"
    remove_column :ai_credentials, :is_default
  end

  def down
    add_column :ai_credentials, :is_default, :boolean, null: false, default: false

    add_index :ai_credentials, [:user_id, :provider],
              unique: true,
              where: "is_default = TRUE",
              name: "index_ai_credentials_on_user_provider_default"

    # Restore is_default from users.default_ai_credential_id
    execute <<~SQL
      UPDATE ai_credentials
      SET is_default = TRUE
      WHERE id IN (SELECT default_ai_credential_id FROM users WHERE default_ai_credential_id IS NOT NULL)
    SQL

    remove_reference :users, :default_ai_credential,
                     foreign_key: { to_table: :ai_credentials },
                     null: true
  end
end
