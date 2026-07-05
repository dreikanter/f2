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

    # No link to detect — an explicit "Follow with AI" bridge, or an input that
    # isn't a URL — goes straight to a draft AI feed (Mode A→B bridge, spec §1).
    return handle_ai_bridge if ai_mode? || source_url.nil?

    return handle_success_status if feed_identification.success?

    if feed_identification.new_record? || feed_identification.failed?
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

    case feed_identification.status
    when "processing"
      handle_processing_status
    when "success"
      handle_success_status
    when "failed"
      handle_failed_status
    end
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

  def handle_failed_status
    code = feed_identification.error.presence || "generic"
    message = t("feed_identifications.failures.#{code}", default: :"feed_identifications.failures.generic")
    render(identification_error(error: message))
  end

  def identification_error(error:)
    {
      turbo_stream: turbo_stream.replace(
        "feed-form",
        partial: "feeds/identification_error",
        locals: { input: raw_input, error: error }
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
    @raw_input ||= params[:input].to_s
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
