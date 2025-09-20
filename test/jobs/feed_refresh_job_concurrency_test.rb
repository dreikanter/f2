require "test_helper"

class FeedRefreshJobConcurrencyTest < ActiveJob::TestCase
  def feed
    @feed ||= create(:feed, loader: "http", processor: "rss", normalizer: "rss")
  end

  test "allows sequential processing of same feed" do
    execution_count = 0

    original_method = FeedRefreshWorkflow.instance_method(:execute)
    FeedRefreshWorkflow.define_method(:execute) do
      execution_count += 1
    end

    FeedRefreshJob.perform_now(feed.id)
    FeedRefreshJob.perform_now(feed.id)

    assert_equal 2, execution_count, "Both sequential jobs should execute"

  ensure
    FeedRefreshWorkflow.define_method(:execute, original_method) if original_method
  end

  test "allows concurrent processing of different feeds" do
    feed1 = create(:feed, loader: "http", processor: "rss", normalizer: "rss")
    feed2 = create(:feed, loader: "http", processor: "rss", normalizer: "rss")

    execution_tracker = {}

    original_method = FeedRefreshWorkflow.instance_method(:execute)
    FeedRefreshWorkflow.define_method(:execute) do
      execution_tracker[feed.id] = true
    end

    thread1 = Thread.new { FeedRefreshJob.perform_now(feed1.id) }
    thread2 = Thread.new { FeedRefreshJob.perform_now(feed2.id) }

    thread1.join
    thread2.join

    assert execution_tracker[feed1.id], "Feed 1 should have been processed"
    assert execution_tracker[feed2.id], "Feed 2 should have been processed"
    assert_equal 2, execution_tracker.keys.count, "Both feeds should have been processed"

  ensure
    FeedRefreshWorkflow.define_method(:execute, original_method) if original_method
  end
end
