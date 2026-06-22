class AddFeedIdStatusIndexToPosts < ActiveRecord::Migration[8.2]
  def change
    add_index :posts, [:feed_id, :status]
  end
end
