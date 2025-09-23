class RemoveServiceColumnsFromFeeds < ActiveRecord::Migration[8.1]
  def change
    remove_column :feeds, :loader, :string
    remove_column :feeds, :processor, :string
    remove_column :feeds, :normalizer, :string
  end
end
