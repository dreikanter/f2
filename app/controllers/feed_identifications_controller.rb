class FeedIdentificationsController < ApplicationController
  include StatePolling

  rate_limit to: 10, within: 1.minute, by: -> { Current.user.id }, only: :create, with: -> {
    message = "Too many attempts in a row. Give it a minute, then try again."
    render throttled_entry_form(message).merge(status: :too_many_requests)
  }

  def create
    # Sourceless mode: nothing to detect, the webhook profile is the destination.
    return handle_webhook_submission if webhook_mode?

    # Mode B (an explicit "Follow with AI") goes straight to a draft AI feed.
    return handle_prompt_submission if ai_mode?

    return render(blank_input_error) if raw_url.blank?

    # A non-link input re-renders the form with the AI panel carrying the
    # text, so switching the mode radio is the bridge.
    return render(not_a_link_error) if source_url.nil?

    # A working result is shown as-is and an in-flight check keeps polling;
    # any settled failure re-runs detection, so resubmitting re-checks it.
    return present_result if feed_identification.working?

    unless feed_identification.persisted? && feed_identification.processing?
      restarted = feed_identification.restart_detection
      # A losing concurrent submit skips the enqueue; the winner owns the
      # in-flight detection.
      FeedIdentificationJob.perform_later(Current.user.id, source_url) if restarted
    end

    render(entry_form(url: source_url, checking: true))
  end

  def show
    unless feed_identification.persisted?
      return render(identification_error(error: "That check expired. Please try again."))
    end

    return handle_processing_status if feed_identification.processing?

    present_result
  end

  def destroy
    original_url = feed_identification.persisted? ? feed_identification.input : raw_url
    feed_identification.destroy if feed_identification.persisted?

    render entry_form(url: original_url)
  end

  private

  # The AI form submits the text as `prompt`; the link form submits `url`; the
  # webhook form submits a bare `webhook` marker. The param name is the mode.
  def ai_mode?
    params.key?(:prompt)
  end

  def webhook_mode?
    params.key?(:webhook)
  end

  def throttled_entry_form(message)
    if webhook_mode?
      entry_form(mode: "webhook", error: message)
    elsif ai_mode?
      entry_form(mode: "ai", prompt: raw_prompt, error: message)
    else
      entry_form(error: message)
    end
  end

  # No source input; the posting URL is minted when the draft is saved.
  def handle_webhook_submission
    feed = Current.user.feeds.build(feed_profile_key: "webhook")
    render(identification_success(feed, candidates: []))
  end

  # No detection: the prompt is the source. AI feeds default to a daily
  # cadence.
  def handle_prompt_submission
    if raw_prompt.blank?
      return render(entry_form(mode: "ai", error: "Tell AI what to follow — a link or a few words about it."))
    end

    feed = Current.user.feeds.build(feed_profile_key: "llm", params: { "prompt" => raw_prompt }, schedule_interval: "1d")
    render(identification_success(feed, candidates: []))
  end

  def blank_input_error
    entry_form(error: "Enter a link, or a few words describing what to follow.")
  end

  def not_a_link_error
    entry_form(
      prompt: raw_url,
      error: "That doesn't look like a link. Paste a feed or page URL — or switch to “Follow with AI” to go after it anyway."
    )
  end

  def feed_identification
    @feed_identification ||= FeedIdentification.find_or_initialize_by(user: Current.user, input: identification_input)
  end

  def handle_processing_status
    if feed_identification.invalid_processing?
      feed_identification.destroy
      return render(identification_error(error: "Error identifying feed. Oh no."))
    end

    # Past the deadline: drop the row so the checking state stops with an
    # explanation instead of freezing.
    if feed_identification.started_at < polling_timeout.ago
      feed_identification.destroy
      return render(identification_error(error: "This check is taking longer than expected — the link may not be responding. Please try again."))
    end

    head :no_content
  end

  # The feed form when a candidate works, otherwise the couldn't-reach or
  # no-feed hint.
  def present_result
    return present_working if feed_identification.working?
    return render(unreachable_error) if feed_identification.unreachable?

    render(no_feed_error)
  end

  def present_working
    suggested = feed_identification.suggested_candidate
    profile_key = suggested&.profile_key
    source_key = FeedProfile.source_key_for(profile_key)
    # The form carries the URL the feed will actually read; for a page URL
    # that's the discovered feed, and a note explains the swap.
    source_url = feed_identification.source_url_for(profile_key)
    discovered = source_url != feed_identification.input

    if editing?
      # The proposed source and profile apply in memory only; the
      # confirming PATCH persists them. Operational edits were saved on
      # the propose PATCH.
      profile_changed = edit_feed.feed_profile_key != profile_key
      feed = edit_feed.tap do |f|
        f.feed_profile_key = profile_key
        f.params = (f.params || {}).merge(source_key => source_url)
      end

      # A source (and possibly profile) change is pending confirmation, so the
      # form surfaces the matching duplicate-risk warning.
      render(identification_success(feed, candidates: feed_identification.working_candidates,
                                          source_changed: true, profile_changed: profile_changed,
                                          source_discovered: discovered))
    else
      feed = Current.user.feeds.build(
        params: { source_key => source_url },
        feed_profile_key: profile_key,
        name: suggested&.title&.truncate(Feed::NAME_MAX_LENGTH, omission: "…")
      )
      render(identification_success(feed, candidates: feed_identification.working_candidates,
                                          source_discovered: discovered))
    end
  end

  # Creation states re-render the entry form: frozen while checking, or
  # enabled with the hint. Every response swaps the same "feed-form" frame.
  def entry_form(mode: "link", url: raw_url, prompt: nil, checking: false, error: nil)
    { turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/form_collapsed",
      locals: { mode: mode, url: url, prompt: prompt, checking: checking, error: error }
    ) }
  end

  def expanded_form(feed, **options)
    { turbo_stream: turbo_stream.replace("feed-form", FeedFormComponent.new(feed: feed, **options)) }
  end

  # The engine is fixed in edit, so there is no AI mode to switch to, just
  # the hint under the source field.
  def edit_form(attempted_url:, error: nil)
    expanded_form(edit_feed, attempted_url: attempted_url, source_error: error)
  end

  def identification_error(error:, url: raw_url, prompt: nil)
    return edit_form(attempted_url: url, error: error) if editing?

    entry_form(url: url, prompt: prompt, error: error)
  end

  # Terminal: reachable, but no profile reads it. Creation offers the AI
  # bridge; edit just invites another link.
  def no_feed_error
    if editing?
      return identification_error(error: "We couldn't pull any posts from that link. Try a different one — your current source is untouched.")
    end

    identification_error(
      prompt: raw_url,
      error: "We couldn't pull any posts from that link. Try a different one — or switch to “Follow with AI”, which can follow pages without a feed."
    )
  end

  # Transient: nothing connected. Resubmitting re-runs detection, and in
  # creation the AI panel stays available as a secondary escape.
  def unreachable_error
    if editing?
      return identification_error(error: "We couldn't reach that link. It might be a temporary hiccup — save again to retry, or keep the current source.")
    end

    identification_error(
      prompt: raw_url,
      error: "We couldn't reach that link. It might be a temporary hiccup — try again in a moment, or switch to “Follow with AI”."
    )
  end

  def identification_success(feed, candidates: [], source_changed: false, profile_changed: false,
                             source_discovered: false)
    expanded_form(feed, candidates: candidates,
                        source_changed: source_changed, profile_changed: profile_changed,
                        source_discovered: source_discovered)
  end

  # The feed being edited, or nil in the creation
  # flow. Scoped to the current user so a forged feed_id can't reach another's.
  def edit_feed
    return @edit_feed if defined?(@edit_feed)

    @edit_feed = params[:feed_id].present? ? Current.user.feeds.find_by(id: params[:feed_id]) : nil
  end

  def editing?
    edit_feed.present?
  end

  def raw_url
    @raw_url ||= params[:url].to_s.strip
  end

  def raw_prompt
    @raw_prompt ||= params[:prompt].to_s.strip
  end

  # The canonical source URL for detection (silent scheme-fix), or nil when the
  # input isn't a link — in which case the entry flow bridges to the AI profile.
  def source_url
    return @source_url if defined?(@source_url)

    @source_url = SourceLink.canonical(raw_url)
  end

  # Key the identification by the canonical URL when we have one. The polling
  # #show requests carry that canonical URL back as `url`, so this stays stable
  # across the detection lifecycle.
  def identification_input
    source_url || raw_url
  end
end
