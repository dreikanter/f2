class Admin::FeedsController < ApplicationController
  include Pagination
  include Sortable
  include FeedListing

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

  def sortable_path(sort_params)
    admin_feeds_path(sort_params)
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
