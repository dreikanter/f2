class AddRefreshIntervalToFeeds < ActiveRecord::Migration[8.2]
  def change
    add_column :feeds, :refresh_interval, :integer
    add_check_constraint :feeds, "refresh_interval > 0", name: "feeds_refresh_interval_positive"
  end
end
