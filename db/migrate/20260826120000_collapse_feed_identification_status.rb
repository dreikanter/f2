# Collapses the identification state into one explicit status. The old
# success/failed pair plus the error code and the candidate verdicts all
# encoded the settled result; the fetcher now writes that result directly,
# so the error column has nothing left to carry.
class CollapseFeedIdentificationStatus < ActiveRecord::Migration[8.0]
  # Old statuses: processing 0, success 1, failed 2.
  # New statuses: processing 0, working 1, unreachable 2, no_feed 3.
  def up
    execute <<~SQL
      UPDATE feed_identifications SET status = CASE
        WHEN status = 1 AND EXISTS (
          SELECT 1 FROM jsonb_array_elements(candidates) c
          WHERE COALESCE(c->>'test_status', '') NOT IN ('failed', 'unreachable')
        ) THEN 1
        WHEN status = 1 AND jsonb_array_length(candidates) > 0 AND NOT EXISTS (
          SELECT 1 FROM jsonb_array_elements(candidates) c
          WHERE COALESCE(c->>'test_status', '') <> 'unreachable'
        ) THEN 2
        WHEN status = 1 THEN 3
        WHEN status = 2 AND error = 'unreachable' THEN 2
        WHEN status = 2 THEN 3
        ELSE 0
      END
    SQL

    remove_column :feed_identifications, :error
  end

  # Restores rows that behave the same under the old derivation; the exact
  # error code a failed row carried is not recoverable.
  def down
    add_column :feed_identifications, :error, :text

    execute <<~SQL
      UPDATE feed_identifications SET error = CASE
        WHEN status = 2 AND jsonb_array_length(candidates) = 0 THEN 'unreachable'
        WHEN status = 3 AND jsonb_array_length(candidates) = 0 THEN 'unidentifiable'
      END
    SQL

    execute <<~SQL
      UPDATE feed_identifications SET status = CASE
        WHEN status IN (2, 3) AND jsonb_array_length(candidates) = 0 THEN 2
        WHEN status IN (1, 2, 3) THEN 1
        ELSE 0
      END
    SQL
  end
end
