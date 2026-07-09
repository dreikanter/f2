# Refresh runs are now one feed_refresh event per run with a lifecycle status
# in metadata, replacing the separate feed_refresh_error type. Fold existing
# events into that shape.
class UnifyFeedRefreshEventTypes < ActiveRecord::Migration[8.2]
  def up
    execute <<~SQL
      UPDATE events
      SET type = 'feed_refresh',
          metadata = jsonb_set(metadata, '{status}', '"failed"', true)
      WHERE type = 'feed_refresh_error'
    SQL

    execute <<~SQL
      UPDATE events
      SET metadata = jsonb_set(metadata, '{status}', '"completed"', true)
      WHERE type = 'feed_refresh' AND metadata ->> 'status' IS NULL
    SQL
  end

  def down
    execute <<~SQL
      UPDATE events
      SET type = 'feed_refresh_error',
          metadata = metadata - 'status'
      WHERE type = 'feed_refresh' AND metadata ->> 'status' = 'failed'
    SQL

    execute <<~SQL
      UPDATE events
      SET metadata = metadata - 'status'
      WHERE type = 'feed_refresh' AND metadata ->> 'status' = 'completed'
    SQL
  end
end
