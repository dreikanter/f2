require "test_helper"

class FeedRefreshJobConcurrencyTest < ActiveJob::TestCase
  def feed
    @feed ||= begin
      profile = create(:feed_profile, loader: "http", processor: "rss", normalizer: "rss")
      create(:feed, feed_profile: profile)
    end
  end

  test "allows concurrent processing of different feeds" do
    profile = create(:feed_profile, loader: "http", processor: "rss", normalizer: "rss")
    feed1 = create(:feed, feed_profile: profile)
    feed2 = create(:feed, feed_profile: profile)

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
