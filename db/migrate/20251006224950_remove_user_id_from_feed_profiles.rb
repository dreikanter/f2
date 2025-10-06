class RemoveUserIdFromFeedProfiles < ActiveRecord::Migration[8.1]
  def change
    remove_reference :feed_profiles, :user, null: false, foreign_key: true, index: true
  end
end
