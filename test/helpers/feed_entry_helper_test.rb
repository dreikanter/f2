require "test_helper"

class FeedEntryHelperTest < ActionView::TestCase
  include FeedEntryHelper

  test "#feed_entry_status_badge_color should return info for pending" do
    assert_equal :info, feed_entry_status_badge_color("pending")
  end

  test "#feed_entry_status_badge_color should return success for processed" do
    assert_equal :success, feed_entry_status_badge_color("processed")
  end

  test "#feed_entry_status_badge_color should return neutral for unknown status" do
    assert_equal :neutral, feed_entry_status_badge_color("unknown")
  end
end
