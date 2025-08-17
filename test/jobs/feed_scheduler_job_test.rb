require "test_helper"

class FeedSchedulerJobTest < ActiveJob::TestCase
  test "schedules enabled feeds that are due" do
    freeze_time do
      feed = create(:feed, :enabled)
      schedule = create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)
      
      assert_enqueued_with(job: FeedRefreshJob, args: [feed.id]) do
        FeedSchedulerJob.perform_now
      end
      
      schedule.reload
      assert schedule.last_run_at.present?
      assert schedule.next_run_at > Time.current
    end
  end

  test "skips disabled feeds" do
    freeze_time do
      feed = create(:feed, :disabled)
      create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)
      
      assert_no_enqueued_jobs(only: FeedRefreshJob) do
        FeedSchedulerJob.perform_now
      end
    end
  end

  test "skips feeds not yet due" do
    freeze_time do
      feed = create(:feed, :enabled)
      create(:feed_schedule, feed: feed, next_run_at: 1.hour.from_now)
      
      assert_no_enqueued_jobs(only: FeedRefreshJob) do
        FeedSchedulerJob.perform_now
      end
    end
  end

  test "handles concurrent updates with optimistic locking" do
    freeze_time do
      feed = create(:feed, :enabled)
      schedule = create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)
      
      # Simulate another process updating the schedule
      FeedSchedule.where(id: schedule.id).update_all(next_run_at: 1.hour.from_now)
      
      assert_no_enqueued_jobs(only: FeedRefreshJob) do
        FeedSchedulerJob.perform_now
      end
    end
  end

  test "creates schedule for feeds without one" do
    freeze_time do
      feed = create(:feed, :enabled)
      # No schedule created
      
      assert_enqueued_with(job: FeedRefreshJob, args: [feed.id]) do
        FeedSchedulerJob.perform_now
      end
      
      feed.reload
      assert feed.feed_schedule.present?
      assert_equal Time.current, feed.feed_schedule.last_run_at
      assert_equal Time.current, feed.feed_schedule.next_run_at
    end
  end
end
