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
    @llm_usage_totals = LlmUsageReport.for_feed(@feed, period: LlmUsageReport::STATS_PERIOD.ago..Time.current).totals
  end

  private

  def sortable_path(sort_params)
    admin_feeds_path(sort_params)
  end

  def recent_events(feed)
    feed.events.recent.limit(MAX_RECENT_EVENTS)
  end

  def pagination_scope
    with_listing_stats(policy_scope([:admin, Feed]))
      .includes(:user, :access_token)
      .order(sortable_order)
  end
end
