class AddServiceAttributesToFeeds < ActiveRecord::Migration[8.1]
  def change
    add_column :feeds, :loader, :string, null: false, default: "http"
    add_column :feeds, :processor, :string, null: false, default: "rss"
    add_column :feeds, :normalizer, :string, null: false, default: "rss"
  end
end
