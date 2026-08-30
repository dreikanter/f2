class AddValidationRuns < ActiveRecord::Migration[8.2]
  def change
    add_column :access_tokens, :validation_run_id, :uuid

    add_column :ai_credentials, :validation_started_at, :datetime
    add_column :ai_credentials, :validation_run_id, :uuid

    add_column :search_credentials, :validation_started_at, :datetime
    add_column :search_credentials, :validation_run_id, :uuid
  end
end
