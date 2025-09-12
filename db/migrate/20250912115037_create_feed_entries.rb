class CreateFeedEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :feed_entries do |t|
      t.references :feed, null: false, foreign_key: true
      t.string :uid, null: false
      t.datetime :published_at
      t.integer :status, default: 0
      t.jsonb :raw_data

      t.timestamps
    end

    add_index :feed_entries, [:feed_id, :uid], unique: true
  end
end
