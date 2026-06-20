class FeedsController < ApplicationController
  include Pagination
  include Sortable
  include FeedStateEvents

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
    authorize Feed
    scope = policy_scope(Feed)
    @active_feed_count = scope.enabled.count
    @inactive_feed_count = scope.disabled.count
    @draft_feed_count = scope.draft.count
    @sortable_presenter = sortable_presenter
    @feeds = paginate_scope
  end

  def new
    @feed = feeds_scope.build
    authorize @feed
  end

  def create
    @feed = feeds_scope.build(create_feed_params)
    authorize @feed

    if @feed.save
      cleanup_feed_identification(@feed.url) if @feed.url

      if require_ai_credentials?
        redirect_to new_ai_credential_path(feed_id: @feed.id)
      elsif require_access_token?
        redirect_to new_access_token_path(feed_id: @feed.id)
      elsif enable_feed?
        enable_and_respond(@feed)
      else
        redirect_to feed_path(@feed), success: success_message_for(@feed)
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @feed = load_feed
    authorize @feed
    @recent_posts = recent_posts(@feed)
    @recent_events = recent_events(@feed)
    @has_llm_usages = @feed.llm_usages.exists?
  end

  def edit
    @feed = load_feed
    authorize @feed
  end

  # Per FR-026/FR-027/FR-028 operational fields (name, target_group, schedule,
  # access_token) edit freely; source-side fields (url, feed_profile_key,
  # params) are not editable from this form and stay anchored to the original
  # detection result. Re-pointing a feed at a different source means creating
  # a new feed.
  def update
    @feed = load_feed
    authorize @feed
    @feed.assign_attributes(update_feed_params)

    # Unticked Enable on an enabled feed = pause request (gate flow skips this
    # because the gate only appears for drafts without usable credentials).
    @feed.state = :disabled if @feed.enabled? && !enable_feed? && !require_ai_credentials? && !require_access_token?

    if @feed.save
      # Capture interval-change signal from the first save before the
      # promotion attempt's save overwrites `saved_changes`.
      interval_changed = @feed.saved_change_to_cron_expression?
      record_feed_disabled(@feed) if @feed.saved_change_to_state? && @feed.disabled?
      cleanup_feed_identification(@feed.url) if @feed.url

      if require_ai_credentials?
        redirect_to new_ai_credential_path(feed_id: @feed.id)
      elsif require_access_token?
        redirect_to new_access_token_path(feed_id: @feed.id)
      elsif enable_feed? && !@feed.enabled?
        promote_and_redirect(@feed, interval_changed)
      else
        @feed.reset_schedule! if interval_changed && @feed.feed_schedule.present?
        redirect_to feed_path(@feed), success: update_message_for(@feed)
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @feed = load_feed
    authorize @feed
    @feed.destroy!
    redirect_to feeds_path, success: "Feed deleted."
  end

  private

  def require_ai_credentials?
    params[:commit] == "save_as_draft_and_add_credentials"
  end

  def require_access_token?
    params[:commit] == "save_as_draft_and_add_token"
  end

  def enable_feed?
    params[:enable_feed] == "1"
  end

  def enable_and_respond(feed)
    if feed.enable
      record_feed_enabled(feed)
      FeedRefreshJob.perform_later(feed.id)
      redirect_to feed_path(feed), success: success_message_for(feed)
    else
      flash.now[:alert] = "Couldn't enable. See issues below."
      render :new, status: :unprocessable_entity
    end
  end

  def promote_and_redirect(feed, interval_changed)
    feed.transaction do
      if feed.enable
        record_feed_enabled(feed)
        feed.reset_schedule! if interval_changed && feed.feed_schedule.present?
      end
    end

    if feed.enabled?
      redirect_to feed_path(feed), success: update_message_for(feed)
    else
      flash.now[:alert] = "Couldn't enable. See issues below."
      render :edit, status: :unprocessable_entity
    end
  end

  def feeds_scope
    current_user.feeds
  end

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

  def recent_events(feed)
    feed.events.user_relevant.recent.limit(MAX_RECENT_EVENTS)
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
      :ai_credential_id,
      :cron_expression,
      :schedule_interval,
      :import_after_enabled,
      :import_after_date,
      :import_after_time,
      :images_only,
      # Only the known input-shape keys are accepted. Anything
      # else inside the params hash would otherwise persist into
      # `feeds.params` jsonb undetected. See the profile schemas.
      params: [:url, :query]
    )
  end

  def create_feed_params
    feed_params
  end

  # Drafts (per FR-007) may still edit source-side fields (url,
  # feed_profile_key, params) because they haven't been confirmed yet. Once a
  # feed transitions out of :draft for the first time (FR-008), those fields
  # lock in for the rest of the feed's lifetime regardless of later
  # pause/resume. Strong params silently drops them for non-drafts.
  def update_feed_params
    always_permitted = %i[
      name description target_group access_token_id ai_credential_id schedule_interval
      import_after_enabled import_after_date import_after_time images_only
    ]
    draft_only_permitted = [:url, :feed_profile_key, { params: %i[url query] }]

    permitted_keys = @feed&.draft? ? always_permitted + draft_only_permitted : always_permitted
    params.require(:feed).permit(*permitted_keys)
  end

  def cleanup_feed_identification(input)
    FeedIdentification.find_by(user: current_user, input: input)&.destroy
  end

  # `#create` only produces `enabled` or `draft` today (the disabled branch is
  # kept as a defensive fallback for any future caller that lands here in the
  # disabled state; `#update` doesn't share this helper).
  def success_message_for(feed)
    if feed.enabled?
      "Feed created and enabled."
    elsif feed.disabled?
      "Feed '#{feed.name}' was successfully created but is currently disabled. " \
        "Enable it from the feed page when you're ready to start importing posts."
    else
      "Feed saved as draft. Continue setup from your feeds list when ready."
    end
  end

  def update_message_for(feed)
    if feed.enabled?
      "Feed '#{feed.name}' was successfully updated. Changes will take effect on the next scheduled refresh."
    elsif feed.disabled?
      "Feed '#{feed.name}' was successfully updated."
    else
      "Draft saved. Finish setup when you're ready to enable it."
    end
  end
end
