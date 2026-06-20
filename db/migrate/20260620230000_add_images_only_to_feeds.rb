class AddImagesOnlyToFeeds < ActiveRecord::Migration[8.2]
  def change
    add_column :feeds, :images_only, :boolean, default: false, null: false
  end
end
