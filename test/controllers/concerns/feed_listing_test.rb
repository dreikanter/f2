require "test_helper"

class FeedListingTest < ActiveSupport::TestCase
  include FeedListing

  test "#sortable_fields should sort feeds by their latest post date" do
    refreshed_at = 3.hours.ago
    feed = create(:feed, last_successful_refresh_at: refreshed_at)
    published_at = 2.hours.ago
    entry = create(:feed_entry, feed: feed, created_at: refreshed_at)
    create(:post, feed: feed, feed_entry: entry, published_at: published_at)

    older_feed = create(:feed)
    create(:post, feed: older_feed, published_at: 1.day.ago)
    listed_feeds = Feed.where(id: [older_feed.id, feed.id])
                      .order(Arel.sql(sortable_fields.fetch(:recent_post).fetch(:order_by) + " DESC"))
    assert_equal [feed.id, older_feed.id], listed_feeds.map(&:id)
    listed_feed = listed_feeds.first

    assert_in_delta refreshed_at.to_f, listed_feed.last_refreshed_at.to_f, 0.001
    assert_in_delta published_at.to_f, listed_feed.most_recent_post_at.to_f, 0.001
  end

  test "#sortable_fields should use successful refreshes without posts for display and sorting" do
    refreshed_at = 1.hour.ago.change(usec: 0)
    empty_feed = create(:feed, last_successful_refresh_at: refreshed_at)
    older_feed = create(:feed, last_successful_refresh_at: 1.day.ago)
    create(:feed_entry, feed: older_feed, created_at: 1.minute.ago)

    listed_feeds = Feed.where(id: [empty_feed.id, older_feed.id])
                       .order(Arel.sql(sortable_fields.fetch(:last_refresh).fetch(:order_by) + " DESC")).to_a

    assert_equal [empty_feed.id, older_feed.id], listed_feeds.map(&:id)
    assert_equal refreshed_at, listed_feeds.first.last_refreshed_at
    assert_nil listed_feeds.first.most_recent_post_at
  end

  test "#sortable_fields should leave refresh time blank until a successful refresh" do
    feed = create(:feed)
    create(:feed_entry, feed: feed)

    listed_feed = Feed.find(feed.id)

    assert_nil listed_feed.last_refreshed_at
  end
end
