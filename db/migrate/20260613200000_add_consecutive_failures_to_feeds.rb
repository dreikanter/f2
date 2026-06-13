class AddConsecutiveFailuresToFeeds < ActiveRecord::Migration[8.2]
  def change
    add_column :feeds, :consecutive_failures, :integer, default: 0, null: false
  end
end
