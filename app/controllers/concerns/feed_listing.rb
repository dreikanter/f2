# Shared feed-list configuration for the user-facing and admin feed
# controllers: the sort-field SQL and the show page's recent-posts query.
# Keeping the raw order_by expressions in one place stops the two copies
# from drifting.
module FeedListing
  extend ActiveSupport::Concern

  MAX_RECENT_POSTS = 5
  MAX_RECENT_EVENTS = 10

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
      order_by: "(SELECT MAX(created_at) FROM feed_entries WHERE feed_entries.feed_id = feeds.id)",
      direction: :desc
    },
    recent_post: {
      title: "Recent Post",
      order_by: "(SELECT MAX(published_at) FROM posts WHERE posts.feed_id = feeds.id)",
      direction: :desc
    }
  }.freeze

  private

  def sortable_fields
    SORTABLE_FIELDS
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
