class EnforceSingleFeedSchedule < ActiveRecord::Migration[8.0]
  def change
    remove_index :feed_schedules, :feed_id
    add_index :feed_schedules, :feed_id, unique: true
  end
end
