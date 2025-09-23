class CreateFeedPreviews < ActiveRecord::Migration[8.1]
  def change
    create_table :feed_previews, id: :uuid do |t|
      t.references :feed, null: true, foreign_key: true, type: :bigint
      t.string :url, null: false
      t.references :feed_profile, null: false, foreign_key: true, type: :bigint
      t.jsonb :data
      t.string :status, null: false, default: 'pending'

      t.timestamps
    end

    add_index :feed_previews, [:url, :feed_profile_id], unique: true, name: 'index_feed_previews_on_url_and_profile'
    add_index :feed_previews, :status
    add_index :feed_previews, :created_at
  end
end
