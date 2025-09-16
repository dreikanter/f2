require "test_helper"

class FeedRefreshJobConcurrencyTest < ActiveJob::TestCase
  def feed
    @feed ||= create(:feed, loader: "http", processor: "rss", normalizer: "rss")
  end

  test "advisory lock integration works" do
    # Test that we can acquire and release advisory locks
    lock_acquired = false

    Feed.with_advisory_lock("test_lock_#{feed.id}") do
      lock_acquired = true
    end

    assert lock_acquired, "Advisory lock should be acquirable"
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