class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.references :feed, null: false, foreign_key: true
      t.references :feed_entry, null: false, foreign_key: true
      t.string :uid, null: false
      t.integer :status, default: 0, null: false
      t.datetime :published_at, null: false
      t.string :source_url, null: false
      t.text :content, default: "", null: false
      t.text :attachment_urls, default: [], null: false, array: true
      t.text :comments, default: [], null: false, array: true
      t.string :freefeed_post_id
      t.text :validation_errors, default: [], null: false, array: true

      t.timestamps
    end

    add_index :posts, [:feed_id, :uid], unique: true
  end
end
