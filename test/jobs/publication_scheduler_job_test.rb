require "test_helper"

class PublicationSchedulerJobTest < ActiveJob::TestCase
  test ".perform_now should kick a publish chain for enabled feeds with enqueued posts" do
    feed = create(:feed, :enabled)
    create(:post, :enqueued, feed: feed)

    assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
      PublicationSchedulerJob.perform_now
    end
  end

  test ".perform_now should skip enabled feeds without enqueued posts" do
    feed = create(:feed, :enabled)
    create(:post, :published, feed: feed)

    assert_no_enqueued_jobs(only: PostPublishJob) do
      PublicationSchedulerJob.perform_now
    end
  end

  test ".perform_now should skip feeds whose publish chain is already running" do
    feed = create(:feed, :enabled)
    create(:post, :enqueued, feed: feed)

    # Hold the chain's lock to simulate a live PostPublishJob; the watchdog must
    # not pile a duplicate kick onto it.
    Feed.with_advisory_lock("post_publish_#{feed.id}") do
      assert_no_enqueued_jobs(only: PostPublishJob) do
        PublicationSchedulerJob.perform_now
      end
    end
  end

  test ".perform_now should skip disabled feeds even with enqueued posts" do
    feed = create(:feed, :disabled)
    create(:post, :enqueued, feed: feed)

    assert_no_enqueued_jobs(only: PostPublishJob) do
      PublicationSchedulerJob.perform_now
    end
  end

  test ".perform_now should enqueue one job per feed regardless of post count" do
    feed = create(:feed, :enabled)
    create_list(:post, 3, :enqueued, feed: feed)

    assert_enqueued_jobs 1, only: PostPublishJob do
      PublicationSchedulerJob.perform_now
    end
  end
end
