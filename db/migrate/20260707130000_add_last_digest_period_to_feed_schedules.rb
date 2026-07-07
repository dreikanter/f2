class AddLastDigestPeriodToFeedSchedules < ActiveRecord::Migration[8.2]
  def change
    add_column :feed_schedules, :last_digest_period, :date
  end
end
