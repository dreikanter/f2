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

  private

  def assert_logs_match(pattern)
    original_logger = Rails.logger
    log_output = StringIO.new
    Rails.logger = Logger.new(log_output)

    yield

    assert_match pattern, log_output.string
  ensure
    Rails.logger = original_logger
  end
end
