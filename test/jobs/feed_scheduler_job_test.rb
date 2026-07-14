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

  test ".perform_now should skip schedules without an explicit next run date" do
    feed = create(:feed, :enabled)
    schedule = create(:feed_schedule, feed: feed, next_run_at: nil)

    assert_no_enqueued_jobs(only: FeedRefreshJob) do
      FeedSchedulerJob.perform_now
    end

    assert_nil schedule.reload.last_run_at
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

  test ".perform_now should ignore feeds without an explicit schedule" do
    feed = create(:feed, :enabled)

    assert_no_enqueued_jobs(only: FeedRefreshJob) do
      FeedSchedulerJob.perform_now
    end

    assert_nil feed.reload.feed_schedule
  end

  test "#refresh? should recreate a schedule deleted after the feed was selected as due" do
    feed = create(:feed, :enabled)
    schedule = create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)
    selected_feed = Feed.due.find(feed.id)
    schedule.destroy!

    assert FeedSchedulerJob.new.send(:refresh?, selected_feed)
    assert_equal Time.current, selected_feed.reload.feed_schedule.last_run_at
    assert_equal Time.current, selected_feed.feed_schedule.next_run_at
  end

  test ".perform_now should ignore an unscheduled feed with a stale due schedule" do
    FeedProfile.stub(:scheduled?, false) do
      feed = create(:feed, :enabled, cron_expression: nil)
      schedule = create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)

      assert_no_enqueued_jobs(only: FeedRefreshJob) do
        FeedSchedulerJob.perform_now
      end

      schedule.reload
      assert_equal 1.hour.ago, schedule.next_run_at
      assert_nil schedule.last_run_at
    end
  end

  test ".perform_now should not adopt schedule-less webhook feeds" do
    feed = create(:feed, :webhook, state: :enabled)

    assert_no_enqueued_jobs(only: FeedRefreshJob) do
      FeedSchedulerJob.perform_now
    end

    assert_nil feed.reload.feed_schedule
  end
end
