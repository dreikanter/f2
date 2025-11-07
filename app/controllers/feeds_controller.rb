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

  def show
    @feed = load_feed
    authorize @feed
    @section = params[:section]
    @recent_posts = recent_posts(@feed)

    if @section && request.format.turbo_stream?
      render turbo_stream: turbo_stream.update("edit-form-container", "")
    end
  end

  def edit
    @feed = load_feed
    authorize @feed
    @section = params[:section]

    if @section && request.format.turbo_stream?
      render turbo_stream: turbo_stream.update(
        "edit-form-container",
        partial: form_template_name,
        locals: { feed: @feed }
      )
    else
      render turbo_stream: turbo_stream.update("edit-form-container", "")
    end
  end

  def update
    feed = load_feed
    authorize feed

    feed.state = :disabled if feed.enabled? && !will_be_complete_after_update?(feed)

    if feed.update(section_params)
      streams = [
        turbo_stream.update("#{section}-content", partial: display_template_name, locals: { feed: feed }),
        turbo_stream.update("edit-form-container", "")
      ]

      if section == "content-source"
        streams << turbo_stream.update("feed-title", feed.name)
      end

      render turbo_stream: streams
    else
      render turbo_stream: turbo_stream.update("edit-form-container", partial: form_template_name, locals: { feed: feed })
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
    policy_scope(Feed).includes(:feed_entries, :posts).order(sortable_order)
  end

  def form_template_name
    section == "content-source" ? "content_source_form" : "#{section}_form"
  end

  def display_template_name
    section == "content-source" ? "content_source_display" : "#{section}_display"
  end

  def load_feed
    policy_scope(Feed).find(params[:id])
  end

  def section
    params.require(:section)
  end

  def section_params
    case section
    when "content-source"
      content_source_params
    when "reposting"
      reposting_params
    when "scheduling"
      scheduling_params
    else
      feed_params
    end
  end

  def content_source_params
    params[:feed].permit(:name, :url, :feed_profile_key)
  end

  def reposting_params
    permitted_params = params[:feed].permit(:access_token_id, :target_group)

    unless Current.user.access_tokens.active.exists?
      permitted_params[:access_token_id] = nil
    end

    permitted_params
  end

  def scheduling_params
    params[:feed].permit(:cron_expression, :import_after)
  end

  def will_be_complete_after_update?(feed)
    updated_feed = feed.dup
    updated_feed.assign_attributes(section_params)
    updated_feed.can_be_enabled?
  end

  def feed_params
    params.require(:feed).permit(
      :name,
      :url,
      :cron_expression,
      :feed_profile_key,
      :import_after,
      :description,
      :access_token_id,
      :target_group
    )
  end
end
