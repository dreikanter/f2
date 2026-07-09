class FeedsController < ApplicationController
  include Pagination
  include Sortable
  include FeedStateEvents
  include StatePolling
  include FeedListing

  # Operational fields, editable on any feed.
  ALWAYS_PERMITTED_PARAMS = %i[
    name
    description
    target_group
    access_token_id
    ai_credential_id
    ai_model
    schedule_interval
    import_after_enabled
    import_after_date
    import_after_time
    images_only
  ].freeze

  # Source-side fields, editable only while a feed is a draft (FR-007/008);
  # once it first leaves :draft they lock in for good.
  DRAFT_ONLY_PERMITTED_PARAMS = [
    :url,
    :feed_profile_key,
    { params: %i[url prompt] }
  ].freeze

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
      cleanup_feed_identification(@feed.source_input)

      if (gate_path = setup_gate_path(@feed))
        redirect_to gate_path
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

  # Operational fields (name, target_group, schedule, access_token) edit freely.
  # A live deterministic feed's source can be re-pointed, but only through
  # detection: a changed source URL re-runs identification and the confirming
  # save applies it only once a working candidate is verified (spec §4). The
  # engine stays fixed — deterministic ↔ AI is a new feed.
  def update
    @feed = load_feed
    authorize @feed

    # A changed deterministic source that isn't yet backed by a verified working
    # candidate hands off to the async detector and paints the §7 states; a
    # confirmed one falls through to the normal save below (with the source
    # applied), so enable/pause/schedule bookkeeping stays in one place. Capture
    # the decision before assign_attributes moves source_input onto the new URL.
    source_change = mode_a_source_change?
    if source_change && !source_change_confirmed?
      return propose_source_redetection(canonical_submitted_url || submitted_source_raw)
    end

    @feed.assign_attributes(update_feed_params)
    # Overwrite the raw submitted URL with the canonical, verified source and its
    # detected profile (the confirm path — spec §4).
    apply_confirmed_source if source_change

    # Unticked Enable on an enabled feed = pause request (gate flow skips this
    # because the gate only appears for drafts without usable credentials).
    gate_path = setup_gate_path(@feed)
    @feed.state = :disabled if @feed.enabled? && !enable_feed? && gate_path.nil?

    if @feed.save
      # Capture interval-change signal from the first save before the
      # promotion attempt's save overwrites `saved_changes`.
      interval_changed = @feed.saved_change_to_cron_expression?
      record_feed_disabled(@feed) if @feed.saved_change_to_state? && @feed.disabled?
      cleanup_feed_identification(@feed.source_input)

      if gate_path
        redirect_to gate_path
      elsif enable_feed? && !@feed.enabled?
        promote_and_redirect(@feed, interval_changed)
      else
        @feed.reset_schedule! if interval_changed
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

  helper_method :mode

  private

  # Entry mode on the new-feed page, normalized from the ?mode tab links.
  def mode
    params[:mode] == "ai" ? "ai" : "link"
  end

  def enable_feed?
    params[:enable_feed] == "1"
  end

  # The user clicked one of the "save draft and set up …" buttons: detour to
  # that setup page instead of finishing on the feed.
  def setup_gate_path(feed)
    case params[:commit]
    when "save_as_draft_and_add_credentials" then new_ai_credential_path(feed_id: feed.id)
    when "save_as_draft_and_add_token" then new_access_token_path(feed_id: feed.id)
    end
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
        feed.reset_schedule! if interval_changed
      end
    end

    if feed.enabled?
      redirect_to feed_path(feed), success: update_message_for(feed)
    else
      flash.now[:alert] = "Couldn't enable. See issues below."
      render :edit, status: :unprocessable_entity
    end
  end

  # True when a live deterministic feed's submitted source URL differs from the
  # one it's anchored to — the only case that routes through re-detection.
  def mode_a_source_change?
    return false unless @feed.persisted? && !@feed.draft?
    return false if FeedProfile.depends_on_ai?(@feed.feed_profile_key)

    submitted_source_raw.present? && submitted_source_raw != @feed.source_input.to_s
  end

  def submitted_source_raw
    @submitted_source_raw ||= params.dig(:feed, :params, :url).to_s.strip
  end

  def submitted_profile_key
    params.dig(:feed, :feed_profile_key)
  end

  def canonical_submitted_url
    return @canonical_submitted_url if defined?(@canonical_submitted_url)

    @canonical_submitted_url = SourceLink.canonical(submitted_source_raw)
  end

  # The settled working identification for the submitted URL, or nil. A source
  # change is confirmed only when one exists and the submitted profile is one of
  # its working candidates — a candidate that actually read the source (spec §4).
  def settled_working_identification
    return @settled_working_identification if defined?(@settled_working_identification)

    fi = canonical_submitted_url && FeedIdentification.find_by(user: current_user, input: canonical_submitted_url)
    @settled_working_identification = (fi&.success? && fi.outcome == :working) ? fi : nil
  end

  def source_change_confirmed?
    fi = settled_working_identification
    fi.present? && fi.working_candidate_profile_keys.include?(submitted_profile_key)
  end

  def apply_confirmed_source
    @feed.url = canonical_submitted_url
    @feed.feed_profile_key = submitted_profile_key
    @feed.source_verified = true
  end

  # Persist the operational edits so they survive the async detection gap, then
  # kick detection and paint the §7 loading state. The source itself waits for a
  # confirmed working candidate; no state transition happens here, so a live feed
  # keeps refreshing its verified source until the new one is confirmed.
  def propose_source_redetection(url)
    return render :edit, status: :unprocessable_entity unless @feed.update(operational_update_params)

    identification = FeedIdentification.find_or_initialize_by(user: current_user, input: url)
    identification.restart_detection!
    FeedIdentificationJob.perform_later(current_user.id, url)

    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/identification_loading",
      locals: { url: url, feed_id: @feed.id, cancel_path: feed_path(@feed), edit_mode: true }
    )
  end

  def operational_update_params
    update_feed_params.except(:params, :feed_profile_key)
  end

  def feeds_scope
    current_user.feeds
  end

  def sortable_path(sort_params)
    feeds_path(sort_params)
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

  # A new feed is a draft, so creation accepts the draft-editable set.
  def create_feed_params
    params.require(:feed).permit(*ALWAYS_PERMITTED_PARAMS, *DRAFT_ONLY_PERMITTED_PARAMS)
  end

  def update_feed_params
    params.require(:feed).permit(*permitted_keys)
  end

  def permitted_keys
    if @feed.draft?
      ALWAYS_PERMITTED_PARAMS + DRAFT_ONLY_PERMITTED_PARAMS
    elsif FeedProfile.depends_on_ai?(@feed.feed_profile_key)
      # A live AI feed's prompt stays editable (spec §4): the uid scheme is
      # unchanged, so a prompt edit carries no duplicate risk (just possible
      # backfill). The url isn't accepted here — an AI feed's source is its prompt.
      ALWAYS_PERMITTED_PARAMS + [{ params: [:prompt] }]
    else
      # A live deterministic feed can move its source, but only through detection
      # (spec §4). The URL rides operational params; the re-detected profile is
      # applied explicitly by the confirm path (from a verified chooser pick), so
      # feed_profile_key stays out of the mass-assignable set here — an unverified
      # profile switch can't leak in.
      ALWAYS_PERMITTED_PARAMS + [{ params: [:url] }]
    end
  end

  def cleanup_feed_identification(input)
    return if input.blank?

    FeedIdentification.find_by(user: current_user, input: input)&.destroy
  end

  def success_message_for(feed)
    if feed.enabled?
      "Feed created and enabled."
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
