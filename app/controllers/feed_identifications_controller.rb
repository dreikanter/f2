class FeedIdentificationsController < ApplicationController
  include StatePolling

  before_action :require_authentication

  rate_limit to: 10, within: 1.minute, by: -> { Current.user.id }, only: :create, with: -> {
    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/identification_error",
      locals: { input: params[:input], error: "Too many identification attempts. Please wait before trying again." }
    ), status: :too_many_requests
  }

  def create
    return render(identification_error(error: "Enter a link, or a few words describing what to follow.")) if raw_input.blank?

    # Mode B (an explicit "Follow with AI") goes straight to a draft AI feed.
    return handle_ai_bridge if ai_mode?

    # Mode A input that isn't a link can't be detected: offer the AI bridge
    # rather than guessing (spec §1) — the user stays in the mode they chose.
    return render(not_a_link_bridge) if source_url.nil?

    # A settled result — a working feed, or a reachable link with no feed — is
    # shown as-is. Everything else kicks off a fresh detection, so the retry
    # state's Retry actually re-checks a couldn't-reach result.
    return present_outcome if settled_identification?

    if feed_identification.new_record? || feed_identification.failed? || retryable_unreachable?
      begin
        feed_identification.update!(
          status: :processing,
          started_at: Time.current,
          candidates: [],
          error: nil
        )
      rescue ActiveRecord::RecordNotUnique
        # Race condition: another process created the record, reload and continue
        feed_identification.reload
      end

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
    original_input = feed_identification.persisted? ? feed_identification.input : raw_input
    feed_identification.destroy if feed_identification.persisted?

    render turbo_stream: turbo_stream.replace(
      "feed-form",
      partial: "feeds/form_collapsed",
      locals: { input: original_input }
    )
  end

  private

  def ai_mode?
    params[:mode] == "ai"
  end

  # Build a draft AI feed straight from the carried input — no detection, the AI
  # profile is the destination and the prompt is the source (Mode A→B bridge).
  def handle_ai_bridge
    feed = Current.user.feeds.build(feed_profile_key: "llm", params: { "prompt" => raw_input })
    render(identification_success(feed, candidates: []))
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
    params_for_input = { source_key => feed_identification.input }

    feed = Current.user.feeds.build(
      params: params_for_input,
      feed_profile_key: profile_key,
      name: suggested&.title&.truncate(Feed::NAME_MAX_LENGTH, omission: "…")
    )

    render(identification_success(feed, candidates: feed_identification.candidates))
  end

  def identification_error(error:, heading: "Feed identification failed")
    {
      turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/identification_error",
        locals: { input: raw_input, error: error, heading: heading }
      )
    }
  end

  def not_a_link_bridge
    identification_error(
      heading: "That doesn't look like a link",
      error: "Follow it with AI instead, or switch back and paste a link."
    )
  end

  # Terminal: the link was reachable but no deterministic profile reads it. The
  # bridge is the way forward (spec §7).
  def no_feed_error
    identification_error(
      heading: "Couldn't pull any posts from that link",
      error: "We couldn't find a feed there — but AI can still follow it, or you can try a different link."
    )
  end

  # Transient: nothing connected. Retrying is the primary path; the bridge is a
  # secondary escape so the state can't dead-end (spec §7).
  def couldnt_reach_retry
    {
      turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/identification_retry",
        locals: { input: raw_input }
      )
    }
  end

  def identification_loading
    {
      turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/identification_loading",
        locals: { input: source_url }
      )
    }
  end

  def identification_success(feed, candidates: [])
    {
      turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/form_expanded",
        locals: { feed: feed, candidates: candidates }
      )
    }
  end

  def raw_input
    @raw_input ||= params[:input].to_s.strip
  end

  # The canonical source URL for detection (silent scheme-fix), or nil when the
  # input isn't a link — in which case the entry flow bridges to the AI profile.
  def source_url
    return @source_url if defined?(@source_url)

    @source_url = SourceLink.canonical(raw_input)
  end

  # Key the identification by the canonical URL when we have one. The polling
  # #show requests carry that canonical URL back as `input`, so this stays stable
  # across the detection lifecycle.
  def identification_input
    source_url || raw_input
  end
end
