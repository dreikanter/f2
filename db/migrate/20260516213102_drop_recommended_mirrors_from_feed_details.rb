class DropRecommendedMirrorsFromFeedDetails < ActiveRecord::Migration[8.2]
  def change
    remove_column :feed_details, :feed_profile_key, :string
    remove_column :feed_details, :title, :string
  end
end
