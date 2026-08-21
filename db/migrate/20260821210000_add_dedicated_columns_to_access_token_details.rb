# First half of retiring access_token_details.data: adds the dedicated
# columns and backfills them. The data column itself is kept (and ignored by
# the model) so still-running old-code containers keep working through the
# deploy; a follow-up migration drops it once this code is live everywhere.
class AddDedicatedColumnsToAccessTokenDetails < ActiveRecord::Migration[8.0]
  def up
    add_column :access_token_details, :freefeed_user_info, :jsonb, default: {}, null: false
    add_column :access_token_details, :managed_groups, :jsonb, default: [], null: false
    add_column :access_token_details, :groups_refresh_state, :string
    add_column :access_token_details, :groups_refresh_requested_at, :datetime
    add_check_constraint :access_token_details,
                         "groups_refresh_state IN ('running', 'failed')",
                         name: "access_token_details_groups_refresh_state_valid"

    execute <<~SQL
      UPDATE access_token_details
      SET freefeed_user_info = COALESCE(data->'user_info', '{}'::jsonb),
          managed_groups = COALESCE(data->'managed_groups', '[]'::jsonb)
    SQL
  end

  def down
    remove_check_constraint :access_token_details, name: "access_token_details_groups_refresh_state_valid"
    remove_column :access_token_details, :freefeed_user_info
    remove_column :access_token_details, :managed_groups
    remove_column :access_token_details, :groups_refresh_state
    remove_column :access_token_details, :groups_refresh_requested_at
  end
end
