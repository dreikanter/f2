class AddIndexToPostsStatus < ActiveRecord::Migration[8.2]
  def change
    add_index :posts, :status
  end
end
