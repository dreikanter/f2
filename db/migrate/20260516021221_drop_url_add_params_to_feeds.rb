class DropUrlAddParamsToFeeds < ActiveRecord::Migration[8.2]
  def up
    add_column :feeds, :params, :jsonb, null: false, default: {}
    remove_column :feeds, :url
  end

  def down
    add_column :feeds, :url, :string, null: false
    remove_column :feeds, :params
  end
end
