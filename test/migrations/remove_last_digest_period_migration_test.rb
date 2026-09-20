require "test_helper"
require_relative "../../db/migrate/20260920150000_remove_last_digest_period_from_feed_schedules"

class RemoveLastDigestPeriodMigrationTest < ActiveSupport::TestCase
  test "#change should roll back and reapply while preserving schedule timestamps" do
    schedule = create(:feed_schedule, last_run_at: 1.hour.ago, next_run_at: 1.hour.from_now)
    last_run_at = schedule.last_run_at
    next_run_at = schedule.next_run_at
    migration = RemoveLastDigestPeriodFromFeedSchedules.new

    migration.migrate(:down)
    assert FeedSchedule.connection.column_exists?(:feed_schedules, :last_digest_period, :date)

    migration.migrate(:up)
    assert_not FeedSchedule.connection.column_exists?(:feed_schedules, :last_digest_period)
    FeedSchedule.reset_column_information

    assert_equal last_run_at, schedule.reload.last_run_at
    assert_equal next_run_at, schedule.next_run_at
  ensure
    FeedSchedule.reset_column_information
  end
end
