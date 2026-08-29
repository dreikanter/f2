class ChangeFeedPreviewRunIdToUuid < ActiveRecord::Migration[8.0]
  def up
    execute "DELETE FROM feed_previews"
    change_column :feed_previews, :run_id, :uuid, using: "run_id::uuid"
  end

  def down
    change_column :feed_previews, :run_id, :string, using: "run_id::text"
  end
end
