class RenameAccessTokenStatusToState < ActiveRecord::Migration[8.2]
  def change
    rename_column :access_tokens, :status, :state
  end
end
