require "test_helper"

class FeedRefreshJobTest < ActiveJob::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "rss")
  end

  test "handles missing feed gracefully" do
    assert_nothing_raised do
      FeedRefreshJob.perform_now(-1)
    end
  end

  test "handles unknown loader gracefully" do
    bad_feed = create(:feed, feed_profile_key: "rss")

    # Mock the loader_class_for to raise ArgumentError for unknown loader
    FeedProfile.stub(:loader_class_for, ->(_key) { raise ArgumentError, "Unknown loader: unknown" }) do
      assert_raises(ArgumentError, "Unknown loader: unknown") do
        FeedRefreshJob.perform_now(bad_feed.id)
      end
    end
  end

  test "handles unknown processor gracefully" do
    bad_feed = create(:feed, feed_profile_key: "rss")

    # Stub the HTTP request that will be made before hitting processor error
    WebMock.stub_request(:get, bad_feed.url).to_return(body: "<rss></rss>", status: 200)

    # Mock the processor_class_for to raise ArgumentError for unknown processor
    FeedProfile.stub(:processor_class_for, ->(_key) { raise ArgumentError, "Unknown processor: unknown" }) do
      assert_raises(ArgumentError, "Unknown processor: unknown") do
        FeedRefreshJob.perform_now(bad_feed.id)
      end
    end
  end

  test "handles unknown normalizer gracefully" do
    bad_feed = create(:feed, feed_profile_key: "rss")

    # Stub with valid RSS content to reach normalizer step
    sample_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>test-entry</guid>
            <title>Test Entry</title>
            <description>Test description</description>
          </item>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, bad_feed.url).to_return(body: sample_rss, status: 200)

    # Mock the normalizer_class_for to raise ArgumentError for unknown normalizer
    FeedProfile.stub(:normalizer_class_for, ->(_key) { raise ArgumentError, "Unknown normalizer: unknown" }) do
      assert_raises(ArgumentError, "Unknown normalizer: unknown") do
        FeedRefreshJob.perform_now(bad_feed.id)
      end
    end
  end

  test "handles advisory lock failure gracefully" do
    feed = create(:feed, feed_profile_key: "rss")

    # Mock the advisory lock to always fail
    Feed.stub(:with_advisory_lock, ->(*args) { raise WithAdvisoryLock::FailedToAcquireLock.new("Could not acquire lock") }) do
      # Should not raise an exception
      assert_nothing_raised do
        FeedRefreshJob.perform_now(feed.id)
      end
    end
  end
end
