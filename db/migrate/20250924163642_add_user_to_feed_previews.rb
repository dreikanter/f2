class AddUserToFeedPreviews < ActiveRecord::Migration[8.1]
  def change
    add_reference :feed_previews, :user, null: false, foreign_key: true
  end
end
