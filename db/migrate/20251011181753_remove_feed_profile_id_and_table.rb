class RemoveFeedProfileIdAndTable < ActiveRecord::Migration[8.1]
  def change
    remove_column :feeds, :feed_profile_id, :integer
    remove_column :feed_previews, :feed_profile_id, :integer
    drop_table :feed_profiles
  end
end
