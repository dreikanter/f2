class Admin::FeedsController < ApplicationController
  include Pagination
  include Sortable

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

  def index
    authorize [:admin, Feed]
    @sortable_presenter = sortable_presenter
    @feeds = paginate_scope
  end

  def show
    @feed = Feed.find(params[:id])
    authorize [:admin, @feed]
    @recent_posts = recent_posts(@feed)
    @recent_events = recent_events(@feed)
    @has_llm_usages = @feed.llm_usages.exists?
  end

  private

  def sortable_fields
    SORTABLE_FIELDS
  end

  def sortable_path(sort_params)
    admin_feeds_path(sort_params)
  end

  def recent_posts(feed)
    feed
      .posts
      .includes(:feed_entry)
      .preload(feed: :access_token)
      .order(published_at: :desc)
      .limit(MAX_RECENT_POSTS)
  end

  def recent_events(feed)
    feed.events.recent.limit(MAX_RECENT_EVENTS)
  end

  def pagination_scope
    policy_scope([:admin, Feed])
      .includes(:user, :access_token, :feed_entries, :posts)
      .order(sortable_order)
  end
end
