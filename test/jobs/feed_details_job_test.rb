require "test_helper"

class FeedDetailsJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  test "should handle missing user gracefully" do
    non_existent_user_id = -1
    url = "http://example.com/feed.xml"

    assert_nothing_raised do
      FeedDetailsJob.perform_now(non_existent_user_id, url)
    end
  end
end
