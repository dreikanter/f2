class CreatePostPublications < ActiveRecord::Migration[8.2]
  def up
    remove_column :posts, :next_comment_index, :integer if column_exists?(:posts, :next_comment_index)

    create_table :post_publications, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :post, null: false, type: :uuid, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.integer :attachments_processed_count, default: 0, null: false
      t.text :uploaded_attachment_ids, array: true, default: [], null: false
      t.integer :comments_published_count, default: 0, null: false
      t.timestamps
    end
  end

  def down
    drop_table :post_publications
  end
end
