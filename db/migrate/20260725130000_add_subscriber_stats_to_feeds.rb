class AddSubscriberStatsToFeeds < ActiveRecord::Migration[8.0]
  def change
    add_column :feeds, :subscribers_count, :integer
    add_column :feeds, :subscribers_count_updated_at, :datetime
  end
end
