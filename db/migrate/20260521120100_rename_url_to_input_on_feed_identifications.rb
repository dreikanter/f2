class RenameUrlToInputOnFeedIdentifications < ActiveRecord::Migration[8.2]
  def change
    rename_column :feed_identifications, :url, :input
  end
end
