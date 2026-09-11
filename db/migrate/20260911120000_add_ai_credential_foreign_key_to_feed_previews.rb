class AddAiCredentialForeignKeyToFeedPreviews < ActiveRecord::Migration[8.2]
  def up
    # Previews left behind by an already-deleted credential would block the key.
    execute <<~SQL.squish
      UPDATE feed_previews SET ai_credential_id = NULL
      WHERE ai_credential_id IS NOT NULL
        AND ai_credential_id NOT IN (SELECT id FROM ai_credentials)
    SQL

    add_index :feed_previews, :ai_credential_id
    add_foreign_key :feed_previews, :ai_credentials, on_delete: :nullify
  end

  def down
    remove_foreign_key :feed_previews, :ai_credentials
    remove_index :feed_previews, :ai_credential_id
  end
end
