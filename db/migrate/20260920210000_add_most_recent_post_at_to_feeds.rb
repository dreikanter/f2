class AddMostRecentPostAtToFeeds < ActiveRecord::Migration[8.2]
  def change
    add_column :feeds, :most_recent_post_at, :datetime
  end
end
