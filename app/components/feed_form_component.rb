# The expanded feed form. Also paints the identification states of an
# edit's source re-detection: frozen and polling while a check runs, or
# re-enabled with the failure hint under the source field.
class FeedFormComponent < ViewComponent::Base
  POLLING_STOP_CONDITION = "[data-identification-state='complete'], [data-identification-state='error']"

  def initialize(feed:, candidates: [], source_changed: false, profile_changed: false,
                 checking: false, source_error: nil, attempted_url: nil, source_discovered: false)
    @feed = feed
    @candidates = candidates
    @source_changed = source_changed
    @profile_changed = profile_changed
    @checking = checking
    @source_error = source_error
    @attempted_url = attempted_url
    @source_discovered = source_discovered
  end

  attr_reader :feed, :candidates, :source_error, :attempted_url

  def checking? = @checking
  def source_changed? = @source_changed
  def profile_changed? = @profile_changed

  # The source URL was discovered on the submitted page; a note under the
  # source field explains the swap.
  def source_discovered? = @source_discovered

  # Creation always builds a fresh record, so persistence tells the flows
  # apart.
  def edit_mode?
    feed.persisted?
  end

  # preview-button mounts on the whole form so it can read the selected
  # feed_profile_key and react to candidate changes. While a re-detection
  # runs, the same wrapper freezes the form and polls for the outcome.
  def wrapper_data
    data = {
      identification_state: identification_state,
      controller: checking? ? "preview-button polling" : "preview-button",
      preview_button_endpoint_value: helpers.feed_previews_path,
      preview_button_source_value: feed.source_input,
      preview_button_source_keys_value: preview_source_keys.to_json,
      preview_button_ai_profiles_value: FeedProfile.ai_profile_keys.to_json,
      preview_button_modal_id_value: "feed-preview-modal"
    }
    data.merge!(polling_data) if checking?
    data
  end

  # Profile-key to source-param-key map the preview button reads: offered
  # candidates while the chooser is live, else the feed's own profile.
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

  def cancel_path
    edit_mode? ? helpers.feed_path(feed) : helpers.feeds_path
  end

  # feed_id is nil (and dropped from the URL) for an unpersisted feed.
  def form_data
    {
      controller: "groups",
      groups_endpoint_value: helpers.access_token_groups_path(":access_token_id", feed_id: feed.id),
      groups_refresh_endpoint_value: helpers.access_token_groups_refresh_path(":access_token_id", context: "feed_form", feed_id: feed.id)
    }
  end

  # A single working candidate renders as a read-only annotation instead.
  def show_chooser?
    candidates.size >= 2
  end

  def source_label
    feed.source_input_url? ? "Source URL" : "Source prompt"
  end

  # An AI feed's prompt is its source and stays editable even on a live
  # feed; the uid scheme is unchanged, so no duplicate risk.
  def ai_prompt_editable?
    FeedProfile.depends_on_ai?(feed.feed_profile_key)
  end

  # A changed URL re-runs detection before saving.
  def source_editable?
    edit_mode? && !ai_prompt_editable?
  end

  # A disabled source field submits nothing, so the source travels as a hidden
  # input. Only the source: every other param has a visible control, and a
  # second input under the same name would race it on DOM order.
  # @return [String] the hidden source input, empty when there is no source
  def hidden_source_field
    key = FeedProfile.source_key_for(feed.feed_profile_key)
    value = key && (feed.params || {})[key]
    return "" if value.nil?

    hidden_field_tag("feed[params][#{key}]", value)
  end

  # While the chooser is live any candidate can be submitted, so every
  # candidate's options are rendered and the selected one is kept enabled.
  # @return [Array<String>] profiles whose options the form should carry
  def option_profile_keys
    return candidates.map(&:profile_key) if show_chooser?

    [feed.feed_profile_key].compact
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

  # An inactive token isn't offered, so preselect a working one and say so
  # instead of letting the browser swap silently.
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

  # A profile change reworks post identity, so it defaults the skip-older
  # threshold on; checkbox and panel visibility must agree.
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

  # With required credentials missing, enabling can only fail and the
  # errors would render nowhere; the checkbox locks off and says what's
  # missing. A still-enabled feed keeps its checkbox so pausing works.
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
