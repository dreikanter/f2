class AddFeedToFeedPreviews < ActiveRecord::Migration[8.2]
  def change
    add_reference :feed_previews, :feed, type: :uuid, foreign_key: true
  end
end
