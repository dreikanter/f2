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

  test "#with_listing_stats should use successful refreshes without posts for display and sorting" do
    refreshed_at = 1.hour.ago.change(usec: 0)
    empty_feed = create(:feed, last_successful_refresh_at: refreshed_at)
    older_feed = create(:feed, last_successful_refresh_at: 1.day.ago)
    create(:feed_entry, feed: older_feed, created_at: 1.minute.ago)

    listed_feeds = with_listing_stats(Feed.where(id: [empty_feed.id, older_feed.id]))
                       .order(Arel.sql("#{LAST_REFRESH_SQL} DESC")).to_a

    assert_equal [empty_feed.id, older_feed.id], listed_feeds.map(&:id)
    assert_equal refreshed_at, listed_feeds.first[:listing_last_refreshed_at]
    assert_nil listed_feeds.first[:listing_most_recent_post_date]
  end
end
