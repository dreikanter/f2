require "test_helper"

class FeedEntryHelperTest < ActionView::TestCase
  include FeedEntryHelper

  test "#feed_entry_status_badge_color should return blue for pending" do
    assert_equal :blue, feed_entry_status_badge_color("pending")
  end

  test "#feed_entry_status_badge_color should return green for processed" do
    assert_equal :green, feed_entry_status_badge_color("processed")
  end

  test "#feed_entry_status_badge_color should return gray for unknown status" do
    assert_equal :gray, feed_entry_status_badge_color("unknown")
  end
end
