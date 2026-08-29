class ChangeFeedPreviewRunIdToUuid < ActiveRecord::Migration[8.0]
  def up
    invalid_run_id = select_value(<<~SQL.squish)
      SELECT run_id
      FROM feed_previews
      WHERE run_id IS NOT NULL
        AND NOT pg_input_is_valid(run_id, 'uuid')
      LIMIT 1
    SQL

    if invalid_run_id
      raise ActiveRecord::MigrationError,
            "feed_previews.run_id contains a non-UUID value; clean invalid run IDs before retrying"
    end

    change_column :feed_previews, :run_id, :uuid, using: "run_id::uuid"
  end

  def down
    change_column :feed_previews, :run_id, :string, using: "run_id::text"
  end
end
