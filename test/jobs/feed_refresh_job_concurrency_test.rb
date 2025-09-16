require "test_helper"

class FeedRefreshJobConcurrencyTest < ActiveJob::TestCase
  def feed
    @feed ||= create(:feed, loader: "http", processor: "rss", normalizer: "rss")
  end

  test "logs when concurrent job is skipped due to advisory lock" do
    log_output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(log_output)

    # Mock refresh_feed to avoid loader/processor dependencies
    original_method = FeedRefreshJob.instance_method(:refresh_feed)
    FeedRefreshJob.define_method(:refresh_feed) do |feed|
      # Do nothing - we just want to test the locking
    end

    # Create a job that holds the lock for a while
    job_holder = Thread.new do
      Feed.with_advisory_lock("feed_refresh_#{feed.id}") do
        sleep(0.1) # Hold lock for 100ms
      end
    end

    sleep(0.01) # Let the first thread acquire the lock

    # Try to run a job that should be blocked
    FeedRefreshJob.perform_now(feed.id)

    job_holder.join

    # Should log that the job was skipped
    assert_match(/is already being processed, skipping/, log_output.string)

  ensure
    Rails.logger = original_logger
    FeedRefreshJob.define_method(:refresh_feed, original_method) if original_method
  end

  test "allows sequential processing of same feed" do
    execution_count = 0

    # Track executions by overriding a method
    original_method = FeedRefreshJob.instance_method(:refresh_feed)
    FeedRefreshJob.define_method(:refresh_feed) do |feed|
      execution_count += 1
    end

    # First job
    FeedRefreshJob.perform_now(feed.id)

    # Second job (sequential, not concurrent)
    FeedRefreshJob.perform_now(feed.id)

    # Both sequential jobs should have executed
    assert_equal 2, execution_count, "Both sequential jobs should execute"

  ensure
    # Restore original method
    FeedRefreshJob.define_method(:refresh_feed, original_method) if original_method
  end

  test "allows concurrent processing of different feeds" do
    feed1 = create(:feed, loader: "http", processor: "rss", normalizer: "rss")
    feed2 = create(:feed, loader: "http", processor: "rss", normalizer: "rss")

    execution_tracker = {}

    # Track executions
    original_method = FeedRefreshJob.instance_method(:refresh_feed)
    FeedRefreshJob.define_method(:refresh_feed) do |feed|
      execution_tracker[feed.id] = true
      sleep(0.02) # Brief processing time
    end

    # Run jobs for different feeds concurrently
    thread1 = Thread.new { FeedRefreshJob.perform_now(feed1.id) }
    thread2 = Thread.new { FeedRefreshJob.perform_now(feed2.id) }

    thread1.join
    thread2.join

    # Both feeds should have been processed
    assert execution_tracker[feed1.id], "Feed 1 should have been processed"
    assert execution_tracker[feed2.id], "Feed 2 should have been processed"
    assert_equal 2, execution_tracker.keys.count, "Both feeds should have been processed"

  ensure
    # Restore original method
    FeedRefreshJob.define_method(:refresh_feed, original_method) if original_method
  end
end