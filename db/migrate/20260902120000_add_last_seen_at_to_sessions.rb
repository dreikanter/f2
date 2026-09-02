class AddLastSeenAtToSessions < ActiveRecord::Migration[8.2]
  def up
    add_column :sessions, :last_seen_at, :datetime

    # Before this column existed, updated_at was touched after ten minutes of
    # authenticated activity. A gap shorter than that cannot prove the cookie
    # was reused, so leave those sessions unestablished.
    execute <<~SQL
      UPDATE sessions
      SET last_seen_at = updated_at
      WHERE updated_at >= created_at + INTERVAL '10 minutes'
    SQL

    remove_index :sessions, :user_id
    add_index :sessions, [:user_id, :last_seen_at]
  end

  def down
    remove_index :sessions, [:user_id, :last_seen_at]
    add_index :sessions, :user_id
    remove_column :sessions, :last_seen_at
  end
end
