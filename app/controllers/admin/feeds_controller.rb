class Admin::FeedsController < ApplicationController
  include Pagination

  MAX_RECENT_POSTS = 5
  MAX_RECENT_EVENTS = 10

  def index
    authorize [:admin, Feed]
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
      .order(created_at: :desc)
  end
end
