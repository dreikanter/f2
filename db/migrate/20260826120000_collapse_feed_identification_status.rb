# Collapses the identification state into one explicit status. The old
# success/failed pair plus the error code and the candidate verdicts all
# encoded the settled result; the fetcher now writes that result directly,
# so the error column has nothing left to carry.
#
# Existing rows are scratch state for the add-a-feed flow, destroyed once a
# feed is created and rebuilt on demand, so they are cleared rather than
# remapped: a check in flight reports as expired and the user runs it again.
# Irreversible, and deliberately so; the old error code is not recoverable
# from the status alone.
class CollapseFeedIdentificationStatus < ActiveRecord::Migration[8.0]
  def up
    execute "DELETE FROM feed_identifications"

    remove_column :feed_identifications, :error
  end

  # Refuses rather than omitting `down`: an absent down is a silent no-op that
  # de-registers the migration while leaving the column dropped.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
