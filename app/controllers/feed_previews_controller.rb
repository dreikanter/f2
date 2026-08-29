class FeedPreviewsController < ApplicationController
  include StatePolling

  before_action :load_preview, only: %i[show update]
  before_action :guard_preview, only: %i[create update]

  # Maps each FeedPreview status to the pane partial that renders it. `fetch`
  # makes an unexpected status fail loudly rather than silently fall through.
  STATE_PARTIALS = {
    "pending" => "processing",
    "processing" => "processing",
    "ready" => "ready",
    "failed" => "failed"
  }.freeze

  # AI previews browse the web (Sonnet gather runs 40–120s, plus structuring), so
  # they need a far longer budget than a deterministic fetch or they'd time out
  # mid-run. ~4 minutes at the shared 2.5s poll interval.
  AI_PREVIEW_MAX_POLLS = 98

  # GET /feed_previews/:id, for polling and frame reloads. The row carries its
  # own source and selections, so nothing about the preview travels in the URL.
  def show
    preview.timeout! if timed_out?(preview)
    render_state(preview, inert_while_running: true)
  end

  # POST /feed_previews, asking for a preview of what the form currently holds.
  # Finds or creates the row for (user, profile_key, params_digest), starts a run
  # when it has no fresh result, and replaces the frame with its current state.
  def create
    found = locate_preview
    found = start_run(found) if needs_run?(found)
    found.timeout! if timed_out?(found)
    render_frame(found)
  end

  # PATCH /feed_previews/:id, the explicit refresh. The row already holds the
  # source and selections, so a re-run needs nothing but its id.
  def update
    preview.restart!(search_credential_id: search_credential&.id)
    render_frame(preview)
  end

  helper_method :preview_max_polls, :state_partial

  private

  # Poll cap for the current preview's profile: the longer AI budget for a
  # web-browsing run, the shared default otherwise. Drives both the client
  # poller (view) and the server-side timeout.
  def preview_max_polls(preview)
    FeedProfile.depends_on_ai?(preview.feed_profile_key) ? AI_PREVIEW_MAX_POLLS : polling_max_polls
  end

  def guard_preview
    return render_cleared if source_blank? || !FeedProfile.exists?(profile_key)
    return render_credential_gate if needs_credential_gate?

    render_cleared if invalid_ai_selection?
  end

  # Server-side backstop for the Stimulus button: an AI preview needs owned,
  # active AI and search credentials plus a verified model.
  def invalid_ai_selection?
    return false unless FeedProfile.depends_on_ai?(profile_key)

    ai_credential.blank? || search_credential.blank? || !ai_credential.supports_model?(ai_model)
  end

  def previews
    Current.user.feed_previews
  end

  def load_preview
    @preview = previews.find(params[:id])
  end

  attr_reader :preview

  def digest
    @digest ||= FeedPreview.digest_for(
      profile_key,
      preview_params,
      ai_credential&.id,
      ai_model,
      search_credential&.id
    )
  end

  # Resolve only from the user's own active credentials, so forged ids can't
  # borrow another user's provider keys.
  def ai_credential
    return @ai_credential if defined?(@ai_credential)

    requested = params[:ai_credential_id].presence || preview&.ai_credential_id
    @ai_credential = Current.user.ai_credentials.active.find_by(id: requested)
  end

  def search_credential
    return @search_credential if defined?(@search_credential)

    @search_credential = resolve_search_credential(profile_key, params[:search_credential_id])
  end

  # @param profile_key [String] the preview's profile
  # @param requested_id [String, nil] a credential chosen in the form
  # @return [SearchCredential, nil] the credential backing the run
  def resolve_search_credential(profile_key, requested_id = nil)
    return unless FeedProfile.exists?(profile_key) && FeedProfile.depends_on_ai?(profile_key)

    credentials = Current.user.search_credentials.active
    return credentials.find_by(id: requested_id) if requested_id.present?

    credentials.find_by(id: Current.user.default_search_credential_id) || credentials.first
  end

  def ai_model
    @ai_model ||= params[:ai_model].presence || preview&.ai_model
  end

  def locate_preview
    preview = previews.find_or_initialize_by(feed_profile_key: profile_key, params_digest: digest)
    preview.search_credential_id_for_digest = search_credential&.id
    preview
  end

  def needs_run?(preview)
    preview.new_record? || stale_ready?(preview)
  end

  # Start a fresh run and return the persisted row. If a concurrent request
  # already inserted this (user, profile, source) row, adopt the winner's row
  # rather than enqueuing a duplicate job.
  def start_run(preview)
    preview.search_credential_id_for_digest = search_credential&.id
    preview.assign_attributes(
      params: preview_params,
      ai_credential_id: ai_credential&.id,
      ai_model: ai_model
    )
    preview.restart!(search_credential_id: search_credential&.id)
  rescue ActiveRecord::RecordNotUnique
    previews.find_by!(feed_profile_key: profile_key, params_digest: digest)
  end

  def timed_out?(preview)
    (preview.pending? || preview.processing?) &&
      preview.updated_at < polling_timeout(preview_max_polls(preview)).ago
  end

  # A create is described by the request; an update by the row it names. The
  # fallbacks let one guard cover both.
  def profile_key
    @profile_key ||= params[:profile_key].presence || preview&.feed_profile_key.to_s
  end

  def preview_params
    @preview_params ||= begin
      raw = params[:params]
      hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
      hash ? hash.deep_stringify_keys : (preview&.params || {})
    end
  end

  def stale_ready?(preview)
    preview.ready? && preview.ready_at.present? && preview.ready_at < FeedPreview::PREVIEW_FRESHNESS_WINDOW.ago
  end

  def source_blank?
    FeedProfile.source_input_for(profile_key, preview_params).to_s.strip.blank?
  end

  # Only reached after guard_preview confirmed the profile exists.
  def needs_credential_gate?
    return false unless FeedProfile.depends_on_ai?(profile_key)

    missing_ai_credentials? || missing_search_credentials?
  end

  def missing_ai_credentials?
    !Current.user.ai_credentials.active.exists?
  end

  def missing_search_credentials?
    !Current.user.search_credentials.active.exists?
  end

  # The create response carries the whole frame, so the polling host mounts and
  # takes over from there.
  def render_frame(preview)
    render turbo_stream: turbo_stream.replace(
      "feed-preview",
      partial: "feed_previews/frame",
      locals: { preview: preview }
    )
  end

  def render_state(preview, inert_while_running: false)
    respond_to do |format|
      format.html { render :show, locals: { preview: preview } }
      # Swap only the inner body so the polling host (rendered by `show`) stays
      # mounted across polls; ready/failed bodies carry `data-preview-done`,
      # which trips the poller's stop-condition. While a run is still in flight
      # the poll stays silent so the spinner keeps its animation instead of
      # being redrawn every cycle.
      format.turbo_stream do
        if inert_while_running && (preview.pending? || preview.processing?)
          head :no_content
        else
          render turbo_stream: turbo_stream.update("feed-preview-body", **state_partial(preview))
        end
      end
    end
  end

  def state_partial(preview)
    { partial: "feed_previews/#{STATE_PARTIALS.fetch(preview.status)}", locals: { preview: preview } }
  end

  def render_cleared
    respond_to do |format|
      format.html { render html: helpers.turbo_frame_tag("feed-preview"), layout: false }
      format.turbo_stream { render turbo_stream: turbo_stream.update("feed-preview", "") }
    end
  end

  def render_credential_gate
    gate = {
      partial: "feed_previews/credential_gate",
      locals: {
        profile_key: profile_key,
        missing_ai_credentials: missing_ai_credentials?,
        missing_search_credentials: missing_search_credentials?
      }
    }
    respond_to do |format|
      format.html do
        body = helpers.turbo_frame_tag("feed-preview") { render_to_string(gate).html_safe }
        render html: body, layout: false
      end
      format.turbo_stream { render turbo_stream: turbo_stream.update("feed-preview", **gate) }
    end
  end
end
