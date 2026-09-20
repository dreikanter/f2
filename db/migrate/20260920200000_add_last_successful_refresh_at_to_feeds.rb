class AddLastSuccessfulRefreshAtToFeeds < ActiveRecord::Migration[8.2]
  def up
    add_column :feeds, :last_successful_refresh_at, :datetime

    execute <<~SQL
      UPDATE feeds
      SET last_successful_refresh_at = refreshes.completed_at
      FROM (
        SELECT subject_id, MAX(created_at) AS completed_at
        FROM events
        WHERE subject_type = 'Feed' AND type = 'feed_refresh'
          AND metadata ->> 'status' = 'completed'
        GROUP BY subject_id
      ) AS refreshes
      WHERE feeds.id = refreshes.subject_id
    SQL
  end

  def down
    remove_column :feeds, :last_successful_refresh_at
  end
end
