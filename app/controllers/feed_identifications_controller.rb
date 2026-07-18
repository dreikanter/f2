class FeedIdentificationsController < ApplicationController
  include StatePolling

  rate_limit to: 10, within: 1.minute, by: -> { Current.user.id }, only: :create, with: -> {
    message = "Too many attempts in a row. Give it a minute, then try again."
    state = ai_mode? ? entry_form(mode: "ai", prompt: raw_prompt, error: message) : entry_form(error: message)
    render state.merge(status: :too_many_requests)
  }

  def create
    # Mode B (an explicit "Follow with AI") goes straight to a draft AI feed.
    return handle_prompt_submission if ai_mode?

    return render(blank_input_error) if raw_url.blank?

    # Mode A input that isn't a link can't be detected: the entry form re-renders
    # with the AI panel carrying the text, so switching the mode radio is the
    # bridge (spec §1) — the user stays in the mode they chose.
    return render(not_a_link_error) if source_url.nil?

    # A settled result — a working feed, or a reachable link with no feed — is
    # shown as-is. Everything else kicks off a fresh detection, so resubmitting
    # after a couldn't-reach result actually re-checks it.
    return present_outcome if settled_identification?

    if feed_identification.new_record? || feed_identification.failed? || retryable_unreachable?
      restarted = feed_identification.restart_detection!
      # A losing concurrent submit skips the enqueue: the winner that just
      # created the row owns the in-flight detection, and both requests render
      # the same checking state.
      FeedIdentificationJob.perform_later(Current.user.id, source_url) if restarted
    end

    render(entry_form(url: source_url, checking: true))
  end

  def show
    unless feed_identification.persisted?
      return render(identification_error(error: "That check expired. Please try again."))
    end

    return handle_processing_status if feed_identification.processing?

    present_outcome
  end

  def destroy
    original_url = feed_identification.persisted? ? feed_identification.input : raw_url
    feed_identification.destroy if feed_identification.persisted?

    render feed_form_stream("form_collapsed", url: original_url)
  end

  private

  # The AI form submits the text as `prompt`; the link form submits `url`.
  # The param name is the mode.
  def ai_mode?
    params.key?(:prompt)
  end

  # Build a draft AI feed straight from the prompt — no detection, the AI
  # profile is the destination and the prompt is the source. AI feeds default
  # to a daily cadence (spec §1).
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

    # Past the deadline: drop the row and re-enable the form with the message,
    # so the checking state stops with an explanation instead of freezing.
    if feed_identification.started_at < polling_timeout.ago
      feed_identification.destroy
      return render(identification_error(error: "This check is taking longer than expected — the link may not be responding. Please try again."))
    end

    head :no_content
  end

  # A finished identification worth showing without re-detecting: a working feed
  # or a reachable-but-featureless link. A couldn't-reach result is deliberately
  # excluded so resubmitting re-runs detection rather than re-rendering itself.
  def settled_identification?
    feed_identification.success? && feed_identification.outcome != :unreachable
  end

  # A prior success whose candidates were all unreachable — retrying should
  # re-detect rather than re-render the same couldn't-reach state.
  def retryable_unreachable?
    feed_identification.success? && feed_identification.outcome == :unreachable
  end

  # Present the finished identification by how many candidates actually work
  # (spec §7): the feed form when at least one does, otherwise the form re-renders
  # with the transient couldn't-reach hint or the terminal no-feed one.
  def present_outcome
    case feed_identification.outcome
    when :working then handle_success_status
    when :unreachable then render(unreachable_error)
    else render(no_feed_error)
    end
  end

  def handle_success_status
    suggested = feed_identification.suggested_candidate
    profile_key = suggested&.profile_key
    source_key = FeedProfile.source_key_for(profile_key)

    if editing?
      # Re-render the feed being edited with the proposed source + profile
      # applied in memory only; the confirming PATCH persists it after the
      # source-verified guard clears (spec §4). Operational edits were saved
      # on the propose PATCH, so the reloaded record already carries them.
      profile_changed = edit_feed.feed_profile_key != profile_key
      feed = edit_feed.tap do |f|
        f.feed_profile_key = profile_key
        f.params = (f.params || {}).merge(source_key => feed_identification.input)
      end

      # A source (and possibly profile) change is pending confirmation, so the
      # form surfaces the matching duplicate-risk warning (spec §4).
      render(identification_success(feed, candidates: feed_identification.working_candidates,
                                          source_changed: true, profile_changed: profile_changed))
    else
      feed = Current.user.feeds.build(
        params: { source_key => feed_identification.input },
        feed_profile_key: profile_key,
        name: suggested&.title&.truncate(Feed::NAME_MAX_LENGTH, omission: "…")
      )
      render(identification_success(feed, candidates: feed_identification.working_candidates))
    end
  end

  # Every response in this flow swaps the same "feed-form" frame; partial names
  # are relative to feeds/.
  def feed_form_stream(partial, **locals)
    { turbo_stream: turbo_stream.replace("feed-form", partial: "feeds/#{partial}", locals: locals) }
  end

  # Creation states re-render the entry form itself (spec §1/§7): frozen while
  # checking, or enabled with the hint under the active mode's input.
  def entry_form(mode: "link", url: raw_url, prompt: nil, checking: false, error: nil)
    feed_form_stream("form_collapsed", mode: mode, url: url, prompt: prompt, checking: checking, error: error)
  end

  # Edit states re-render the edit form — the engine is fixed (spec §4), so
  # there's no AI mode to switch to, just the hint under the source field.
  def edit_form(attempted_url:, error: nil)
    feed_form_stream("form_expanded", feed: edit_feed, edit_mode: true,
                                      attempted_url: attempted_url, source_error: error)
  end

  def identification_error(error:, url: raw_url, prompt: nil)
    return edit_form(attempted_url: url, error: error) if editing?

    entry_form(url: url, prompt: prompt, error: error)
  end

  # Terminal: the link was reachable but no deterministic profile reads it. In
  # creation the AI mode is the way forward (spec §7) and the panel carries the
  # link over; in edit it just invites another link.
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
  # creation the AI panel stays available as a secondary escape (spec §7).
  def unreachable_error
    if editing?
      return identification_error(error: "We couldn't reach that link. It might be a temporary hiccup — save again to retry, or keep the current source.")
    end

    identification_error(
      prompt: raw_url,
      error: "We couldn't reach that link. It might be a temporary hiccup — try again in a moment, or switch to “Follow with AI”."
    )
  end

  def identification_success(feed, candidates: [], source_changed: false, profile_changed: false)
    feed_form_stream("form_expanded", feed: feed, candidates: candidates, edit_mode: editing?,
                                      source_changed: source_changed, profile_changed: profile_changed)
  end

  # The feed being edited (spec §4 source re-detection), or nil in the creation
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
