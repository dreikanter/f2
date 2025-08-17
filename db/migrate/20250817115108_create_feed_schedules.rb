class CreateFeedSchedules < ActiveRecord::Migration[8.0]
  def change
    create_table :feed_schedules do |t|
      t.references :feed, null: false, foreign_key: true
      t.datetime :next_run_at
      t.datetime :last_run_at

      t.timestamps
    end
  end
end
