require "test_helper"

class FeedSchedulerJobTest < ActiveJob::TestCase
  setup { freeze_time }

  teardown { unfreeze_time }

  test ".perform_now should schedule enabled feeds that are due" do
    feed = create(:feed, :enabled)
    schedule = create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)

    assert_enqueued_with(job: FeedRefreshJob, args: [feed.id]) do
      FeedSchedulerJob.perform_now
    end

    schedule.reload
    assert schedule.last_run_at.present?
    assert schedule.next_run_at > Time.current
  end

  test ".perform_now should skip disabled feeds" do
    feed = create(:feed, :disabled)
    create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)

    assert_no_enqueued_jobs(only: FeedRefreshJob) do
      FeedSchedulerJob.perform_now
    end
  end

  test ".perform_now should skip feeds not yet due" do
    feed = create(:feed, :enabled)
    create(:feed_schedule, feed: feed, next_run_at: 1.hour.from_now)

    assert_no_enqueued_jobs(only: FeedRefreshJob) do
      FeedSchedulerJob.perform_now
    end
  end

  test ".perform_now should handle concurrent updates with optimistic locking" do
    feed = create(:feed, :enabled)
    schedule = create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)

    # Simulate another process updating the schedule
    FeedSchedule.where(id: schedule.id).update_all(next_run_at: 1.hour.from_now)

    assert_no_enqueued_jobs(only: FeedRefreshJob) do
      FeedSchedulerJob.perform_now
    end
  end

  test ".perform_now should create schedule for feeds without one" do
    feed = create(:feed, :enabled)

    assert_enqueued_with(job: FeedRefreshJob, args: [feed.id]) do
      FeedSchedulerJob.perform_now
    end

    feed.reload
    assert feed.feed_schedule.present?
    assert_equal Time.current, feed.feed_schedule.last_run_at
    assert_equal Time.current, feed.feed_schedule.next_run_at
  end
end
