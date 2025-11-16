class FeedsController < ApplicationController
  include Pagination
  include Sortable

  MAX_RECENT_POSTS = 5

  SORTABLE_FIELDS = {
    name: {
      title: "Name",
      order_by: "LOWER(feeds.name)",
      direction: :asc
    },
    status: {
      title: "Status",
      order_by: "CASE WHEN feeds.state = 1 THEN 0 ELSE 1 END",
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
    authorize Feed
    scope = policy_scope(Feed)
    @active_feed_count = scope.enabled.count
    @inactive_feed_count = scope.disabled.count
    @sortable_presenter = sortable_presenter
    @feeds = paginate_scope
  end

  def new
    @feed = Feed.new
    authorize @feed
  end

  def create
    @feed = Current.user.feeds.build(feed_params)
    authorize @feed

    if @feed.save
      cleanup_feed_identification(@feed.url)
      redirect_to feed_path(@feed), notice: "Feed was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @feed = load_feed
    authorize @feed
    @recent_posts = recent_posts(@feed)
  end

  def edit
    @feed = load_feed
    authorize @feed
  end

  def update
    @feed = load_feed
    authorize @feed

    if @feed.update(feed_params)
      cleanup_feed_identification(@feed.url)
      redirect_to feed_path(@feed), notice: "Feed was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @feed = load_feed
    authorize @feed
    @feed.destroy!
    redirect_to feeds_path, notice: "Feed was successfully deleted."
  end

  private

  def sortable_fields
    SORTABLE_FIELDS
  end

  def sortable_path(sort_params)
    feeds_path(sort_params)
  end

  def recent_posts(feed)
    feed
      .posts
      .includes(:feed_entry)
      .preload(feed: :access_token)
      .order(published_at: :desc)
      .limit(MAX_RECENT_POSTS)
  end

  def pagination_scope
    policy_scope(Feed).includes(:feed_entries, :posts, :access_token).order(sortable_order)
  end

  def load_feed
    policy_scope(Feed).find(params[:id])
  end

  def feed_params
    params.require(:feed).permit(
      :url,
      :name,
      :feed_profile_key,
      :description,
      :target_group,
      :access_token_id,
      :cron_expression,
      :schedule_interval,
      :state
    )
  end

  def cleanup_feed_identification(url)
    FeedDetail.find_by(user: Current.user, url: url)&.destroy
  end
end
