require "test_helper"

class FeedRefreshJobTest < ActiveJob::TestCase
  def feed
    @feed ||= create(:feed, loader: "http", processor: "rss", normalizer: "rss")
  end

  test "handles missing feed gracefully" do
    assert_nothing_raised do
      FeedRefreshJob.perform_now(-1)
    end
  end

  test "handles unknown loader gracefully" do
    bad_feed = create(:feed, loader: "unknown", processor: "rss", normalizer: "rss")

    assert_raises(ArgumentError, "Unknown loader: unknown") do
      FeedRefreshJob.perform_now(bad_feed.id)
    end
  end

  test "handles unknown processor gracefully" do
    bad_feed = create(:feed, loader: "http", processor: "unknown", normalizer: "rss")

    assert_raises(ArgumentError, "Unknown processor: unknown") do
      FeedRefreshJob.perform_now(bad_feed.id)
    end
  end

  test "handles unknown normalizer gracefully" do
    bad_feed = create(:feed, loader: "http", processor: "rss", normalizer: "unknown")

    assert_raises(ArgumentError, "Unknown normalizer: unknown") do
      FeedRefreshJob.perform_now(bad_feed.id)
    end
  end

  test "handles advisory lock failure gracefully" do
    feed = create(:feed, loader: "http", processor: "rss", normalizer: "rss")

    # Mock the advisory lock to always fail
    Feed.stub(:with_advisory_lock, ->(*args) { raise WithAdvisoryLock::FailedToAcquireLock.new("Could not acquire lock") }) do
      # Should not raise an exception
      assert_nothing_raised do
        FeedRefreshJob.perform_now(feed.id)
      end
    end
  end
end
