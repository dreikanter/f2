class AddLastSuccessfulRefreshAtToFeeds < ActiveRecord::Migration[8.2]
  def change
    add_column :feeds, :last_successful_refresh_at, :datetime
  end
end
