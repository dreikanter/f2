class AddScopesToAccessTokens < ActiveRecord::Migration[8.0]
  def up
    add_column :access_tokens, :scopes, :string, array: true, null: false, default: []

    # Existing tokens predate the column, so their real scopes are unknown until
    # something re-reads them. Seed the set Feeder asks for: an empty list would
    # gate every one of them, and disable them on their next validation.
    execute <<~SQL
      UPDATE access_tokens
      SET scopes = ARRAY['read-my-info', 'read-users-info', 'manage-posts']::varchar[]
    SQL
  end

  def down
    remove_column :access_tokens, :scopes
  end
end
