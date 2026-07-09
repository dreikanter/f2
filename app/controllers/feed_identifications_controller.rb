class FeedIdentificationsController < ApplicationController
  include StatePolling

  before_action :require_authentication

  rate_limit to: 10, within: 1.minute, by: -> { Current.user.id }, only: :create, with: -> {
    render identification_error(
      url: params[:url].presence || params[:prompt],
      error: "Too many identification attempts. Please wait before trying again."
    ).merge(status: :too_many_requests)
  }

  def create
    # Mode B (an explicit "Follow with AI") goes straight to a draft AI feed.
    return handle_ai_bridge if ai_mode?

    return render(blank_input_error) if raw_url.blank?

    # Mode A input that isn't a link can't be detected: offer the AI bridge
    # rather than guessing (spec §1) — the user stays in the mode they chose.
    return render(not_a_link_bridge) if source_url.nil?

    # A settled result — a working feed, or a reachable link with no feed — is
    # shown as-is. Everything else kicks off a fresh detection, so the retry
    # state's Retry actually re-checks a couldn't-reach result.
    return present_outcome if settled_identification?

    if feed_identification.new_record? || feed_identification.failed? || retryable_unreachable?
      feed_identification.restart_detection!
      FeedIdentificationJob.perform_later(Current.user.id, source_url)
    end

    render(identification_loading)
  end

  def show
    unless feed_identification.persisted?
      return render(identification_error(error: "Identification session expired. Please try again."))
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

  # The AI form (and the bridge buttons) submit the text as `prompt`; the link
  # form submits `url`. The param name is the mode.
  def ai_mode?
    params.key?(:prompt)
  end

  # Build a draft AI feed straight from the carried prompt — no detection, the AI
  # profile is the destination and the prompt is the source (Mode A→B bridge).
  # AI feeds default to a daily cadence (spec §1).
  def handle_ai_bridge
    return render(blank_input_error) if raw_prompt.blank?

    feed = Current.user.feeds.build(feed_profile_key: "llm", params: { "prompt" => raw_prompt }, schedule_interval: "1d")
    render(identification_success(feed, candidates: []))
  end

  def blank_input_error
    identification_error(error: "Enter a link, or a few words describing what to follow.")
  end

  def feed_identification
    @feed_identification ||= FeedIdentification.find_or_initialize_by(user: Current.user, input: identification_input)
  end

  def handle_processing_status
    if feed_identification.invalid_processing?
      feed_identification.destroy
      return render(identification_error(error: "Error identifying feed. Oh no."))
    end

    # Past the deadline: drop the row and show the friendly error so the spinner
    # stops with a message instead of spinning forever.
    if feed_identification.started_at < polling_timeout.ago
      feed_identification.destroy
      return render(identification_error(error: "Feed identification is taking longer than expected. The feed URL may not be responding. Please try again."))
    end

    head :no_content
  end

  # A finished identification worth showing without re-detecting: a working feed
  # or a reachable-but-featureless link. A couldn't-reach result is deliberately
  # excluded so its Retry re-runs detection rather than re-rendering itself.
  def settled_identification?
    feed_identification.success? && feed_identification.outcome != :unreachable
  end

  # A prior success whose candidates were all unreachable — retrying should
  # re-detect rather than re-render the same couldn't-reach state.
  def retryable_unreachable?
    feed_identification.success? && feed_identification.outcome == :unreachable
  end

  # Present the finished identification by how many candidates actually work
  # (spec §7): the feed form when at least one does, otherwise the transient
  # retry state (couldn't reach) or the terminal error that offers the AI bridge.
  def present_outcome
    case feed_identification.outcome
    when :working then handle_success_status
    when :unreachable then render(couldnt_reach_retry)
    else render(no_feed_error)
    end
  end

  def handle_success_status
    suggested = feed_identification.suggested_candidate
    profile_key = suggested&.profile_key
    source_key = FeedProfile.source_key_for(profile_key) || "url"

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

  def identification_error(error:, heading: "Feed identification failed", url: raw_url)
    feed_form_stream("identification_error", **base_locals, url: url, error: error, heading: heading)
  end

  # When re-detecting an existing deterministic feed the engine is fixed, so the
  # AI bridge isn't offered (spec §4) — the copy just points back to a link.
  def not_a_link_bridge
    return identification_error(heading: "That doesn't look like a link", error: "Enter a feed or page URL to check it.") if editing?

    identification_error(
      heading: "That doesn't look like a link",
      error: "Follow it with AI instead, or switch back and paste a link."
    )
  end

  # Terminal: the link was reachable but no deterministic profile reads it. In
  # creation the bridge is the way forward (spec §7); in edit the engine is fixed,
  # so it just invites another link.
  def no_feed_error
    return identification_error(heading: "Couldn't pull any posts from that link", error: "We couldn't find a feed there — try a different link, or cancel to keep the current one.") if editing?

    identification_error(
      heading: "Couldn't pull any posts from that link",
      error: "We couldn't find a feed there — but AI can still follow it, or you can try a different link."
    )
  end

  # Transient: nothing connected. Retrying is the primary path; the bridge is a
  # secondary escape so the state can't dead-end (spec §7).
  def couldnt_reach_retry
    feed_form_stream("identification_retry", **base_locals, url: raw_url)
  end

  def identification_loading
    feed_form_stream("identification_loading", **base_locals, url: source_url)
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

  # Common locals the §7 partials read to route back to the right place: the
  # feed_id keeps re-detection in the edit context, cancel_path returns to the
  # feed (not the feeds index), and edit_mode suppresses the AI bridge.
  def base_locals
    { feed_id: edit_feed&.id, cancel_path: (editing? ? feed_path(edit_feed) : feeds_path), edit_mode: editing? }
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
