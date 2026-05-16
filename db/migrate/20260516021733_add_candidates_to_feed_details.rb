class AddCandidatesToFeedDetails < ActiveRecord::Migration[8.2]
  def change
    add_column :feed_details, :candidates, :jsonb, null: false, default: []
  end
end
