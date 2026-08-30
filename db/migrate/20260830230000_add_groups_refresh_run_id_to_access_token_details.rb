class AddGroupsRefreshRunIdToAccessTokenDetails < ActiveRecord::Migration[8.0]
  def change
    add_column :access_token_details, :groups_refresh_run_id, :uuid
  end
end
