class AddLastSeenAtToSessions < ActiveRecord::Migration[8.2]
  def up
    add_column :sessions, :last_seen_at, :datetime
    add_column :users, :last_seen_at, :datetime

    execute <<~SQL
      UPDATE sessions
      SET last_seen_at = updated_at
    SQL
    execute <<~SQL
      UPDATE users
      SET last_seen_at = activity.last_seen_at
      FROM (
        SELECT user_id, MAX(last_seen_at) AS last_seen_at
        FROM sessions
        GROUP BY user_id
      ) AS activity
      WHERE users.id = activity.user_id
    SQL
    change_column_null :sessions, :last_seen_at, false

    remove_index :sessions, :user_id
    add_index :sessions, [:user_id, :last_seen_at]
    add_index :sessions, :last_seen_at
  end

  def down
    remove_index :sessions, [:user_id, :last_seen_at]
    add_index :sessions, :user_id
    remove_column :sessions, :last_seen_at
    remove_column :users, :last_seen_at
  end
end
