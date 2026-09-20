class AddFeedActivityTimestamps < ActiveRecord::Migration[8.2]
  def change
    add_column :feeds, :last_successful_refresh_at, :datetime
    add_column :feeds, :most_recent_post_at, :datetime
  end
end
