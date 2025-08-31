require "test_helper"

class FeedRefreshJobTest < ActiveJob::TestCase
  test "handles missing feed gracefully" do
    # Should not raise error for non-existent feed
    assert_nothing_raised do
      FeedRefreshJob.perform_now(-1)
    end
  end

  test "finds and processes existing feed" do
    feed = create(:feed)

    # Job should find the feed and process it without error
    # Since actual implementation is TODO, we just verify the job completes
    assert_nothing_raised do
      FeedRefreshJob.perform_now(feed.id)
    end
  end
end
