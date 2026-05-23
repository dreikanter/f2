class FeedsController < ApplicationController
  include Pagination
  include Sortable

  helper_method :active_access_tokens?

  MAX_RECENT_POSTS = 5

  SORTABLE_FIELDS = begin
    enabled_sort_position = 0
    other_sort_position = 1
    {
      name: {
        title: "Name",
        order_by: "LOWER(feeds.name)",
        direction: :asc
      },
      status: {
        title: "Status",
        order_by: "CASE WHEN feeds.state = #{Feed.states[:enabled]} THEN #{enabled_sort_position} ELSE #{other_sort_position} END",
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
    }
  end.freeze

  def index
    authorize Feed
    scope = policy_scope(Feed)
    @active_feed_count = scope.enabled.count
    @inactive_feed_count = scope.disabled.count
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
    @feed.preview_token = params[:preview_token]
    @feed.state = params[:enable_feed] == "1" ? :enabled : :draft

    case attempt_save(@feed)
    when :enabled, :draft_saved
      @feed.reset_schedule! if @feed.enabled? && @feed.feed_schedule.nil?
      cleanup_feed_identification(@feed.url) if @feed.url
      redirect_to feed_path(@feed), notice: success_message_for(@feed)
    when :draft_fallback, :failed
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

  # Per FR-026/FR-027/FR-028 operational fields (name, target_group, schedule,
  # access_token) edit freely; source-side fields (url, feed_profile_key,
  # params) are not editable from this form and stay anchored to the original
  # detection result. Re-pointing a feed at a different source means creating
  # a new feed.
  def update
    @feed = load_feed
    authorize @feed

    @feed.preview_token = params[:preview_token]

    if @feed.update(update_feed_params)
      reset_schedule_if_interval_changed
      cleanup_feed_identification(@feed.url)
      redirect_to feed_path(@feed), notice: update_message
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

  def active_access_tokens?
    current_user.access_tokens.active.exists?
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
      :llm_credential_id,
      :cron_expression,
      :schedule_interval,
      # Only the three known input-shape keys are accepted. Anything
      # else inside the params hash would otherwise persist into
      # `feeds.params` jsonb undetected — see the profile schemas.
      params: [:url, :handle, :query]
    )
  end

  def create_feed_params
    feed_params
  end

  # Drafts (per FR-007) may still edit source-side fields (url,
  # feed_profile_key, params) because they haven't been confirmed yet. Once a
  # feed transitions out of :draft for the first time (FR-008), those fields
  # lock in for the rest of the feed's lifetime regardless of later
  # pause/resume — strong params silently drops them for non-drafts.
  def update_feed_params
    always_permitted = %i[name description target_group access_token_id llm_credential_id schedule_interval]
    draft_only_permitted = [:url, :feed_profile_key, { params: %i[url handle query] }]

    permitted_keys = @feed&.draft? ? always_permitted + draft_only_permitted : always_permitted
    params.require(:feed).permit(*permitted_keys)
  end

  def reset_schedule_if_interval_changed
    return unless @feed.saved_change_to_cron_expression?
    return unless @feed.feed_schedule.present?

    @feed.reset_schedule!
  end

  def cleanup_feed_identification(input)
    FeedIdentification.find_by(user: current_user, input: input)&.destroy
  end

  # Save the feed at its target state in one attempt. When the user ticked
  # "Enable feed" but the enabled envelope fails validation, fall back to
  # saving the same data as a draft so typed input is preserved, then re-attach
  # the original enabled-state errors so the form can render them. The
  # single-save shape (rather than save-then-promote) is required so
  # `enabling_requires_recent_preview` fires on new records and on source-side
  # changes — promoting after a successful draft save would self-skip it.
  #
  # Outcomes:
  #   :enabled         — saved at target enabled state
  #   :draft_saved     — saved at target draft state (user didn't request enable)
  #   :draft_fallback  — user requested enable, validation failed, persisted as draft with errors
  #   :failed          — couldn't save even as draft
  def attempt_save(feed)
    attempting_enable = feed.enabled?
    if feed.save
      attempting_enable ? :enabled : :draft_saved
    elsif attempting_enable
      enabled_errors = feed.errors.map { |error| [error.attribute, error.message] }
      feed.state = :draft
      if feed.save
        enabled_errors.each { |attribute, message| feed.errors.add(attribute, message) }
        flash.now[:alert] = "Saved as draft. Fix the issues below to enable."
        :draft_fallback
      else
        :failed
      end
    else
      :failed
    end
  end

  # `#create` only produces `enabled` or `draft` today (the disabled branch is
  # kept as a defensive fallback for any future caller that lands here in the
  # disabled state — `#update` doesn't share this helper).
  def success_message_for(feed)
    case feed.state
    when "enabled"
      "Feed '#{feed.name}' was successfully created and is now active. " \
        "New posts will be checked every #{feed.schedule_display} and published to #{feed.target_group}."
    when "disabled"
      "Feed '#{feed.name}' was successfully created but is currently disabled. " \
        "Enable it from the feed page when you're ready to start importing posts."
    when "draft"
      "Feed saved as draft. Continue setup from your feeds list when ready."
    end
  end

  def update_message
    message = "Feed '#{@feed.name}' was successfully updated."
    message += " Changes will take effect on the next scheduled refresh." if @feed.enabled?
    message
  end
end
