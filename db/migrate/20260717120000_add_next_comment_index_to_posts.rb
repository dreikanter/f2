class AddNextCommentIndexToPosts < ActiveRecord::Migration[8.2]
  def change
    add_column :posts, :next_comment_index, :integer
  end
end
