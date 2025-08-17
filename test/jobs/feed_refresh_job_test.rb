require "test_helper"

class FeedRefreshJobTest < ActiveJob::TestCase
  test "handles missing feed gracefully" do
    assert_nothing_raised do
      FeedRefreshJob.perform_now(-1)
    end
  end
end
