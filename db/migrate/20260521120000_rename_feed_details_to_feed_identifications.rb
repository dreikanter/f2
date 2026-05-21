class RenameFeedDetailsToFeedIdentifications < ActiveRecord::Migration[8.2]
  def change
    rename_table :feed_details, :feed_identifications
  end
end
