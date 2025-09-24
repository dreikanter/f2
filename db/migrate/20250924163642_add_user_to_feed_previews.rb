class AddUserToFeedPreviews < ActiveRecord::Migration[8.1]
  def change
    remove_reference :feed_previews, :feed, foreign_key: true
    add_reference :feed_previews, :user, null: false, foreign_key: true
  end
end
