class AddFeedProfileToFeeds < ActiveRecord::Migration[8.1]
  def change
    add_reference :feeds, :feed_profile, null: true, foreign_key: true
  end
end
