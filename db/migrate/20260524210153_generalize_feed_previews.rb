class GeneralizeFeedPreviews < ActiveRecord::Migration[8.2]
  def up
    add_column :feed_previews, :params, :jsonb, null: false, default: {}
    add_column :feed_previews, :params_digest, :string
    add_column :feed_previews, :ready_at, :datetime
    add_column :feed_previews, :run_id, :string

    # Existing rows are ephemeral previews; discard rather than backfill.
    execute "DELETE FROM feed_previews"

    change_column_null :feed_previews, :params_digest, false
    add_index :feed_previews,
              [:user_id, :feed_profile_key, :params_digest],
              unique: true,
              name: "index_feed_previews_on_owner_profile_digest"

    remove_column :feed_previews, :url, :string, null: false
  end

  def down
    add_column :feed_previews, :url, :string
    execute "DELETE FROM feed_previews"
    change_column_null :feed_previews, :url, false

    remove_index :feed_previews, name: "index_feed_previews_on_owner_profile_digest"
    remove_column :feed_previews, :run_id
    remove_column :feed_previews, :ready_at
    remove_column :feed_previews, :params_digest
    remove_column :feed_previews, :params
  end
end
