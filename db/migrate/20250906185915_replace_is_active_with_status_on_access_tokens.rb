class ReplaceIsActiveWithStatusOnAccessTokens < ActiveRecord::Migration[8.0]
  def up
    add_column :access_tokens, :status, :integer, default: 0, null: false

    # Migrate existing data: active tokens (is_active = true) -> status = 0 (active)
    # inactive tokens (is_active = false) -> status = 1 (inactive)
    execute <<-SQL
      UPDATE access_tokens
      SET status = CASE
        WHEN is_active = true THEN 0
        ELSE 1
      END
    SQL

    remove_column :access_tokens, :is_active
  end

  def down
    add_column :access_tokens, :is_active, :boolean, default: true, null: false

    # Migrate back: status = 0 (active) -> is_active = true
    # status = 1 (inactive) -> is_active = false
    execute <<-SQL
      UPDATE access_tokens
      SET is_active = CASE
        WHEN status = 0 THEN true
        ELSE false
      END
    SQL

    remove_column :access_tokens, :status
  end
end
