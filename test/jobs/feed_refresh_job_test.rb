require "test_helper"

class FeedRefreshJobTest < ActiveJob::TestCase
  test "refreshes feed by id" do
    feed = create(:feed)

    # Capture log output to verify the job ran
    log_output = capture_log do
      FeedRefreshJob.perform_now(feed.id)
    end

    assert_includes log_output, "Refreshing feed: #{feed.name}"
    assert_includes log_output, feed.url
  end

  test "handles missing feed gracefully" do
    # Should not raise an error, just exit early
    assert_nothing_raised do
      FeedRefreshJob.perform_now(999999)
    end
  end

  private

  def capture_log
    log_stream = StringIO.new
    old_logger = Rails.logger
    Rails.logger = Logger.new(log_stream)

    yield

    log_stream.string
  ensure
    Rails.logger = old_logger
  end
end
