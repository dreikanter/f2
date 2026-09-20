class RemoveLastDigestPeriodFromFeedSchedules < ActiveRecord::Migration[8.2]
  def change
    remove_column :feed_schedules, :last_digest_period, :date
  end
end
