class CreateJobRuns < ActiveRecord::Migration[8.2]
  def change
    create_table :job_runs do |t|
      t.string :job_class, null: false
      t.string :status, null: false, default: "queued"
      t.string :job_id
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :job_runs, [:job_class, :created_at]
    add_index :job_runs, :job_id, unique: true
  end
end
