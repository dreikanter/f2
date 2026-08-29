class AddRunIdToFeedIdentifications < ActiveRecord::Migration[8.0]
  def change
    add_column :feed_identifications, :run_id, :uuid
  end
end
