class CreateFeedEntryUids < ActiveRecord::Migration[8.1]
  def change
    create_table :feed_entry_uids do |t|
      t.references :feed, null: false, foreign_key: { on_delete: :cascade }
      t.string :uid, null: false
      t.datetime :imported_at, null: false

      t.timestamps
    end

    add_index :feed_entry_uids, [:feed_id, :uid], unique: true
    add_index :feed_entry_uids, :imported_at
  end
end
