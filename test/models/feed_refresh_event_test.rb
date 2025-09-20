require "test_helper"

class FeedRefreshEventTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, loader: "http", processor: "rss", normalizer: "rss")
  end

  test "create_stats creates event with proper attributes" do
    started_time = 1.hour.ago
    completed_time = Time.current
    stats = {
      started_at: started_time,
      completed_at: completed_time,
      total_duration: 3.5,
      new_entries: 5,
      new_posts: 3
    }

    event = FeedRefreshEvent.create_stats(feed: feed, stats: stats)

    assert_equal "feed_refresh_stats", event.type
    assert_equal "info", event.level
    assert_equal feed, event.subject
    assert_equal feed.user, event.user
    assert_equal "Feed refresh completed for #{feed.name}", event.message

    # JSON storage converts times to strings and symbols to strings
    expected_stats = {
      "started_at" => started_time.iso8601(3),
      "completed_at" => completed_time.iso8601(3),
      "total_duration" => 3.5,
      "new_entries" => 5,
      "new_posts" => 3
    }
    assert_equal expected_stats, event.metadata["stats"]
  end

  test "create_stats works with empty stats" do
    event = FeedRefreshEvent.create_stats(feed: feed)

    assert_equal "feed_refresh_stats", event.type
    assert_equal({}, event.metadata["stats"])
  end

  test "create_error creates event with error details" do
    error = StandardError.new("Test error message")
    error.set_backtrace(["line1", "line2", "line3"])
    stage = "process_feed_contents"
    stats = { "new_entries" => 2 }

    event = FeedRefreshEvent.create_error(
      feed: feed,
      error: error,
      stage: stage,
      stats: stats
    )

    assert_equal "feed_refresh_error", event.type
    assert_equal "error", event.level
    assert_equal feed, event.subject
    assert_equal feed.user, event.user
    assert_equal "Feed refresh failed at #{stage}: #{error.message}", event.message
    assert_equal stats, event.metadata["stats"]
    assert_equal "StandardError", event.metadata["error"]["class"]
    assert_equal "Test error message", event.metadata["error"]["message"]
    assert_equal stage, event.metadata["error"]["stage"]
    assert_equal ["line1", "line2", "line3"], event.metadata["error"]["backtrace"]
  end
end
