class IndexFeedPreviewsOnUpdatedAt < ActiveRecord::Migration[8.0]
  def change
    remove_index :feed_previews, :created_at
    add_index :feed_previews, :updated_at
  end
end
