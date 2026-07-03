class AddJobIdToJobRuns < ActiveRecord::Migration[8.2]
  def change
    add_column :job_runs, :job_id, :string
    add_index :job_runs, :job_id, unique: true
  end
end
