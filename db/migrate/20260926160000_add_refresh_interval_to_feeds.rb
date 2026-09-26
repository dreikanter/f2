class AddRefreshIntervalToFeeds < ActiveRecord::Migration[8.2]
  def change
    add_column :feeds, :refresh_interval, :integer
  end
end
