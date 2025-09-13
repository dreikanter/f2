class AddAccessTokenToFeeds < ActiveRecord::Migration[8.1]
  def change
    add_reference :feeds, :access_token, null: true, foreign_key: true
  end
end
