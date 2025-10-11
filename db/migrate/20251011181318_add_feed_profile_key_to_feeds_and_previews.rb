class AddFeedProfileKeyToFeedsAndPreviews < ActiveRecord::Migration[8.1]
  def change
    add_column :feeds, :feed_profile_key, :string
    add_column :feed_previews, :feed_profile_key, :string
  end
end
