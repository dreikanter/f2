class CreateFeedDetails < ActiveRecord::Migration[8.2]
  def change
    create_table :feed_details do |t|
      t.references :user, null: false, foreign_key: true
      t.string :url, null: false
      t.integer :status, null: false, default: 0
      t.datetime :started_at
      t.string :feed_profile_key
      t.string :title
      t.text :error

      t.timestamps
    end

    add_index :feed_details, [:user_id, :url]
  end
end
