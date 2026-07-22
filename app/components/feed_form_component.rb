# The expanded feed form: the full editor a feed lands on once its source is
# known (or when it needs none) — source identity, name, AI settings, preview,
# reposting settings, advanced options, and the enable checkbox.
#
# Also paints the identification states of an edit's source re-detection
# (spec §4/§7): frozen and polling while a check runs, or re-enabled with the
# failure hint under the source field.
class FeedFormComponent < ViewComponent::Base
  POLLING_STOP_CONDITION = "[data-identification-state='complete'], [data-identification-state='error']"

  def initialize(feed:, candidates: [], source_changed: false, profile_changed: false,
                 checking: false, source_error: nil, attempted_url: nil)
    @feed = feed
    @candidates = candidates
    @source_changed = source_changed
    @profile_changed = profile_changed
    @checking = checking
    @source_error = source_error
    @attempted_url = attempted_url
  end

  attr_reader :feed, :candidates, :source_error, :attempted_url

  def checking? = @checking
  def source_changed? = @source_changed
  def profile_changed? = @profile_changed

  # Editing an existing feed vs. creating one. Every caller passes a persisted
  # feed only from the edit flow (creation always builds a fresh record), so
  # the flag needn't travel as a separate parameter.
  def edit_mode?
    feed.persisted?
  end

  # preview-button is mounted on the whole form so it can read the selected
  # feed_profile_key (radios or hidden field) and react to candidate changes;
  # the button and the modal's frame are nested targets within it. While an
  # edit's source re-detection runs (spec §4), the same wrapper freezes the
  # form and polls for the outcome; a failure re-renders it enabled with the
  # hint under the source field.
  def wrapper_data
    data = {
      identification_state: identification_state,
      controller: checking? ? "preview-button polling" : "preview-button",
      preview_button_endpoint_value: helpers.feed_preview_path,
      preview_button_source_value: feed.source_input,
      preview_button_source_keys_value: preview_source_keys.to_json,
      preview_button_ai_profiles_value: FeedProfile.ai_profile_keys.to_json,
      preview_button_modal_id_value: "feed-preview-modal"
    }
    data.merge!(polling_data) if checking?
    data
  end

  # Profile-key → source-param-key map the preview button reads to build
  # preview requests: every offered candidate while the chooser is live,
  # otherwise just the feed's own profile.
  def preview_source_keys
    if show_chooser?
      candidates.to_h { |candidate| [candidate.profile_key, FeedProfile.source_key_for(candidate.profile_key)] }
    else
      { feed.feed_profile_key => FeedProfile.source_key_for(feed.feed_profile_key) }
    end
  end

  def form_url
    edit_mode? ? helpers.feed_path(feed) : helpers.feeds_path
  end

  def form_method
    edit_mode? ? :patch : :post
  end

  # feed_id is nil (and dropped from the URL) for an unpersisted feed.
  def form_data
    {
      controller: "groups",
      groups_endpoint_value: helpers.access_token_groups_path(":access_token_id", feed_id: feed.id)
    }
  end

  # The chooser is a real choice only with two or more working candidates; one
  # working candidate is shown as a read-only annotation (spec §7). In edit
  # mode it appears only after a source re-detection resolves to multiple
  # candidates.
  def show_chooser?
    candidates.size >= 2
  end

  def source_label
    feed.source_input_url? ? "Source URL" : "Source prompt"
  end

  # For an AI feed the prompt *is* the source: it stays an editable textarea
  # throughout, including edits to a live feed — the uid scheme is unchanged,
  # so there's no duplicate risk, at most some older posts backfilled (spec §4).
  def ai_prompt_editable?
    FeedProfile.depends_on_ai?(feed.feed_profile_key)
  end

  # A deterministic feed's URL is editable when editing an existing feed — a
  # change re-runs detection before saving (spec §4).
  def source_editable?
    edit_mode? && !ai_prompt_editable?
  end

  def source_url_value
    attempted_url || feed.source_input
  end

  # Reworking a live feed's prompt may pull in older posts; a draft's prompt
  # can change freely.
  def prompt_backfill_warning?
    edit_mode? && !feed.draft?
  end

  def feed_type_summary
    helpers.candidate_summary(feed.feed_profile_key, feed.source_input)
  end

  def webhook_endpoint_hint
    feed.persisted? ? "You'll find both on the feed's page." : "Save the feed to get the endpoint and token."
  end

  def name_hint
    if feed.name.present?
      "You can edit this name if you'd like."
    elsif feed.sourceless?
      "Choose a name for this feed."
    else
      "We couldn't automatically detect a name. Please enter one."
    end
  end

  def active_tokens
    @active_tokens ||= feed.user.access_tokens.active.order(:host)
  end

  # A token that went inactive isn't offered in the select, so the feed's own
  # choice can't be kept — preselect a working token and say so below, instead
  # of letting the browser swap silently.
  def token_swap?
    feed.access_token.present? && !feed.access_token.active?
  end

  def selected_token_id
    return active_tokens.first&.id if token_swap?

    feed.access_token_id || active_tokens.first&.id
  end

  def token_options
    options_from_collection_for_select(active_tokens, :id, :display_name, selected_token_id)
  end

  def selected_schedule_interval
    feed.schedule_interval || Feed::DEFAULT_SCHEDULE_INTERVAL
  end

  # A profile change reworks how posts are identified, so it defaults the
  # skip-older-posts threshold on (spec §4); checkbox and panel visibility
  # must agree.
  def import_after_on?
    feed.import_after_enabled || profile_changed?
  end

  # Seed today when a profile change turned the threshold on, so "on" reads as
  # a complete cutoff rather than a blank field.
  def import_after_date_value
    feed.import_after_date || (Date.current.iso8601 if profile_changed?)
  end

  def import_after_time_value
    feed.import_after_time.presence || "00:00"
  end

  # Memoized so the rendered section and the enable-gate checks share one
  # instance (and its credential lookups).
  def ai_settings(form)
    @ai_settings ||= FeedAiSettingsComponent.new(feed: feed, form: form)
  end

  # When a setup gate replaced the token or credential fields, enabling can
  # only fail — and the failure's errors would render inside the missing
  # fields, i.e. nowhere. The checkbox locks off and says what's missing
  # instead. A (legacy) still-enabled feed keeps an interactive checkbox so
  # unchecking-to-pause stays available.
  def enable_blocked?(form)
    enable_missing(form).any? && !feed.enabled?
  end

  def enable_missing(form)
    @enable_missing ||= [].tap do |missing|
      missing << "a FreeFeed access token" if active_tokens.empty?
      next unless ai_settings(form).section_visible?

      missing << "AI credentials" unless ai_settings(form).credentials?
      missing << "search credentials" unless ai_settings(form).search_credentials?
    end
  end

  def enable_checked?(form)
    !enable_blocked?(form) && (helpers.params[:enable_feed] == "1" || feed.enabled?)
  end

  def enable_label_classes(form)
    "block font-semibold #{enable_blocked?(form) ? 'text-muted' : 'text-heading'} mb-0"
  end

  def enable_hint(form)
    if enable_blocked?(form)
      "Add #{enable_missing(form).to_sentence} first, then you can enable this feed."
    elsif feed.scheduled?
      "Start checking for new posts and publish them to FreeFeed."
    else
      "Enable this feed so its webhook endpoint can publish to FreeFeed."
    end
  end

  def submit_label
    checking? ? "Checking…" : "Save feed"
  end

  def submit_classes
    "#{helpers.primary_button_classes} disabled:bg-brand disabled:opacity-60 " \
      "disabled:cursor-not-allowed disabled:hover:bg-brand"
  end

  private

  def identification_state
    return "checking" if checking?
    return "error" if source_error

    "complete"
  end

  def polling_data
    {
      polling_indicate_busy_value: false,
      polling_endpoint_value: helpers.feed_identifications_path(url: attempted_url, feed_id: feed.id),
      polling_interval_value: helpers.polling_interval_ms,
      polling_max_polls_value: helpers.polling_max_polls,
      polling_stop_condition_value: POLLING_STOP_CONDITION
    }
  end
end
