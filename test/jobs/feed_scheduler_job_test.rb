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

  test ".perform_now should preserve due AI schedules while AI is unavailable" do
    credential = create(:ai_credential, :active)
    feed = create(:feed, :enabled, user: credential.user, feed_profile_key: "llm",
                                  ai_credential: credential, ai_model: "claude-sonnet-4-6",
                                  params: { "prompt" => "ruby news" }, search_credential: nil)
    schedule = create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)

    assert_no_enqueued_jobs(only: FeedRefreshJob) do
      FeedSchedulerJob.perform_now
    end

    assert_equal 1.hour.ago, schedule.reload.next_run_at
    assert_nil schedule.last_run_at
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

  test ".perform_now should not claim a schedule already advanced by another invocation" do
    feed = create(:feed, :enabled)
    create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)
    stale_feed = Feed.due.includes(:feed_schedule).find(feed.id)
    first_invocation = FeedSchedulerJob.new

    assert_enqueued_jobs 1, only: FeedRefreshJob do
      FeedSchedulerJob.perform_now
      claimed_schedule = feed.reload.feed_schedule.attributes

      assert_not first_invocation.send(:refresh?, stale_feed)
      assert_equal claimed_schedule, feed.feed_schedule.reload.attributes
    end
  end

  test ".perform_now should ignore feeds without an explicit schedule" do
    feed = create(:feed, :enabled)

    assert_no_enqueued_jobs(only: FeedRefreshJob) do
      FeedSchedulerJob.perform_now
    end

    assert_nil feed.reload.feed_schedule
  end

  test ".perform_now should ignore an unscheduled feed with a stale due schedule" do
    feed = create(:feed, :webhook, state: :enabled)
    schedule = create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)

    assert_no_enqueued_jobs(only: FeedRefreshJob) do
      FeedSchedulerJob.perform_now
    end

    schedule.reload
    assert_equal 1.hour.ago, schedule.next_run_at
    assert_nil schedule.last_run_at
  end

  test ".perform_now should not adopt schedule-less webhook feeds" do
    feed = create(:feed, :webhook, state: :enabled)

    assert_no_enqueued_jobs(only: FeedRefreshJob) do
      FeedSchedulerJob.perform_now
    end

    assert_nil feed.reload.feed_schedule
  end
end
