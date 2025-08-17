require "test_helper"

class FeedRefreshJobTest < ActiveJob::TestCase
  test "processes valid feed" do
    feed = create(:feed)
    
    assert_nothing_raised do
      FeedRefreshJob.perform_now(feed.id)
    end
  end

  test "handles missing feed gracefully" do
    assert_nothing_raised do
      FeedRefreshJob.perform_now(-1)
    end
  end
end
