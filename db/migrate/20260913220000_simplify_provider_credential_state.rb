class SimplifyProviderCredentialState < ActiveRecord::Migration[8.2]
  def up
    # Workers must be stopped during this deployment. Unfinished checks cannot
    # safely resume across the change in credential state semantics.
    supersede_credential_operations

    [:ai_credentials, :search_credentials].each do |table|
      add_column table, :active, :boolean, default: false, null: false
      execute <<~SQL
        UPDATE #{table}
        SET active = CASE state
          WHEN 0 THEN FALSE
          WHEN 1 THEN FALSE
          WHEN 2 THEN TRUE
          WHEN 3 THEN FALSE
          ELSE FALSE
        END
      SQL
      remove_index table, [:user_id, :state]
      remove_column table, :state
      add_index table, [:user_id, :active]
    end
  end

  def down
    supersede_credential_operations

    [:ai_credentials, :search_credentials].each do |table|
      add_column table, :state, :integer, default: 0, null: false
      execute "UPDATE #{table} SET state = CASE WHEN active THEN 2 ELSE 3 END"
      remove_index table, [:user_id, :active]
      remove_column table, :active
      add_index table, [:user_id, :state]
    end
  end

  private

  def supersede_credential_operations
    execute <<~SQL
      UPDATE operation_runs
      SET status = 5, finished_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
      WHERE subject_type IN ('AiCredential', 'SearchCredential')
        AND kind IN (0, 2) AND status IN (0, 1)
    SQL
  end
end
