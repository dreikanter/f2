class DropUrlAddParamsToFeeds < ActiveRecord::Migration[8.2]
  def up
    add_column :feeds, :params, :jsonb, null: false, default: {}

    execute <<~SQL.squish
      UPDATE feeds
      SET params = jsonb_build_object('url', url)
      WHERE url IS NOT NULL
    SQL

    remove_column :feeds, :url
  end

  def down
    add_column :feeds, :url, :string

    execute <<~SQL.squish
      UPDATE feeds
      SET url = params ->> 'url'
    SQL

    change_column_null :feeds, :url, false
    remove_column :feeds, :params
  end
end
