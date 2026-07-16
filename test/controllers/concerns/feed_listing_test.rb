require "test_helper"

class FeedListingTest < ActiveSupport::TestCase
  include FeedListing

  test "#with_listing_stats should select aggregate activity timestamps" do
    feed = create(:feed)
    refreshed_at = 3.hours.ago
    published_at = 2.hours.ago
    entry = create(:feed_entry, feed: feed, created_at: refreshed_at)
    create(:post, feed: feed, feed_entry: entry, published_at: published_at)

    listed_feed = with_listing_stats(Feed.where(id: feed.id)).first

    assert_in_delta refreshed_at.to_f, listed_feed[:listing_last_refreshed_at].to_f, 0.001
    assert_in_delta published_at.to_f, listed_feed[:listing_most_recent_post_date].to_f, 0.001
  end
end
