class AddTargetGroupToFeeds < ActiveRecord::Migration[8.1]
  def change
    add_column :feeds, :target_group, :string, limit: 80
  end
end
