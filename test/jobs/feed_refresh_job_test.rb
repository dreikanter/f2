require "test_helper"

class FeedRefreshJobTest < ActiveJob::TestCase
  def feed
    @feed ||= begin
      profile = create(:feed_profile, loader: "http", processor: "rss", normalizer: "rss")
      create(:feed, feed_profile: profile)
    end
  end

  test "handles missing feed gracefully" do
    assert_nothing_raised do
      FeedRefreshJob.perform_now(-1)
    end
  end

  test "handles unknown loader gracefully" do
    bad_profile = create(:feed_profile, loader: "unknown", processor: "rss", normalizer: "rss")
    bad_feed = create(:feed, feed_profile: bad_profile)

    assert_raises(ArgumentError, "Unknown loader: unknown") do
      FeedRefreshJob.perform_now(bad_feed.id)
    end
  end

  test "handles unknown processor gracefully" do
    bad_profile = create(:feed_profile, loader: "http", processor: "unknown", normalizer: "rss")
    bad_feed = create(:feed, feed_profile: bad_profile)

    # Stub the HTTP request that will be made before hitting processor error
    WebMock.stub_request(:get, bad_feed.url).to_return(body: "<rss></rss>", status: 200)

    assert_raises(ArgumentError, "Unknown processor: unknown") do
      FeedRefreshJob.perform_now(bad_feed.id)
    end
  end

  test "handles unknown normalizer gracefully" do
    bad_profile = create(:feed_profile, loader: "http", processor: "rss", normalizer: "unknown")
    bad_feed = create(:feed, feed_profile: bad_profile)

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

    assert_raises(ArgumentError, "Unknown normalizer: unknown") do
      FeedRefreshJob.perform_now(bad_feed.id)
    end
  end

  test "handles advisory lock failure gracefully" do
    profile = create(:feed_profile, loader: "http", processor: "rss", normalizer: "rss")
    feed = create(:feed, feed_profile: profile)

    # Mock the advisory lock to always fail
    Feed.stub(:with_advisory_lock, ->(*args) { raise WithAdvisoryLock::FailedToAcquireLock.new("Could not acquire lock") }) do
      # Should not raise an exception
      assert_nothing_raised do
        FeedRefreshJob.perform_now(feed.id)
      end
    end
  end
end
