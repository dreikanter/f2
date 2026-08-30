class CreateOperationRuns < ActiveRecord::Migration[8.2]
  def up
    create_table :operation_runs, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :subject, polymorphic: true, type: :uuid, null: false
      t.integer :kind, null: false
      t.integer :status, null: false
      t.datetime :started_at
      t.datetime :deadline_at
      t.datetime :finished_at
      t.jsonb :context, default: {}, null: false
      t.timestamps
    end

    add_index :operation_runs,
              [:subject_type, :subject_id, :kind],
              unique: true,
              where: "status IN (0, 1)",
              name: "index_operation_runs_on_active_subject_and_kind"

    remove_column :access_tokens, :validation_started_at
    remove_column :access_tokens, :validation_run_id
    remove_column :ai_credentials, :validation_started_at
    remove_column :ai_credentials, :validation_run_id
    remove_column :search_credentials, :validation_started_at
    remove_column :search_credentials, :validation_run_id
    remove_check_constraint :access_token_details, name: "access_token_details_groups_refresh_state_valid"
    remove_column :access_token_details, :groups_refresh_state
    remove_column :access_token_details, :groups_refresh_requested_at
    remove_column :access_token_details, :groups_refresh_run_id
  end

  def down
    add_column :access_token_details, :groups_refresh_run_id, :uuid
    add_column :access_token_details, :groups_refresh_requested_at, :datetime
    add_column :access_token_details, :groups_refresh_state, :integer
    add_check_constraint :access_token_details,
                         "groups_refresh_state IN (0, 1)",
                         name: "access_token_details_groups_refresh_state_valid"
    add_column :search_credentials, :validation_run_id, :uuid
    add_column :search_credentials, :validation_started_at, :datetime
    add_column :ai_credentials, :validation_run_id, :uuid
    add_column :ai_credentials, :validation_started_at, :datetime
    add_column :access_tokens, :validation_run_id, :uuid
    add_column :access_tokens, :validation_started_at, :datetime

    drop_table :operation_runs
  end
end
