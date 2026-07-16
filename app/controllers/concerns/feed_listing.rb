# Shared feed-list configuration for the user-facing and admin feed
# controllers: sort expressions, listing stats, and recent-post queries.
module FeedListing
  extend ActiveSupport::Concern

  MAX_RECENT_POSTS = 5
  MAX_RECENT_EVENTS = 10

  LAST_REFRESH_SQL = "(SELECT MAX(created_at) FROM feed_entries WHERE feed_entries.feed_id = feeds.id)".freeze
  MOST_RECENT_POST_SQL = "(SELECT MAX(published_at) FROM posts WHERE posts.feed_id = feeds.id)".freeze

  SORTABLE_FIELDS = {
    name: {
      title: "Name",
      order_by: "LOWER(feeds.name)",
      direction: :asc
    },
    status: {
      title: "Status",
      order_by: "CASE feeds.state WHEN #{Feed.states[:draft]} THEN 0 WHEN #{Feed.states[:enabled]} THEN 1 ELSE 2 END",
      direction: :asc
    },
    target_group: {
      title: "Target Group",
      order_by: "LOWER(feeds.target_group)",
      direction: :asc
    },
    last_refresh: {
      title: "Last Refresh",
      order_by: LAST_REFRESH_SQL,
      direction: :desc
    },
    recent_post: {
      title: "Recent Post",
      order_by: MOST_RECENT_POST_SQL,
      direction: :desc
    }
  }.freeze

  private

  def sortable_fields
    SORTABLE_FIELDS
  end

  def with_listing_stats(scope)
    scope.select(
      "feeds.*",
      "#{LAST_REFRESH_SQL} AS listing_last_refreshed_at",
      "#{MOST_RECENT_POST_SQL} AS listing_most_recent_post_date"
    )
  end

  def recent_posts(feed)
    feed
      .posts
      .includes(:feed_entry)
      .preload(feed: :access_token)
      .order(published_at: :desc)
      .limit(MAX_RECENT_POSTS)
  end
end
