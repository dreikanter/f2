class FeedPreviewsController < ApplicationController
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

  # GET /feed_previews/:id, for polling and frame reloads. The row carries its
  # own source and selections, so nothing about the preview travels in the URL.
  def show
    render_state(preview, inert_while_running: true)
  end

  # POST /feed_previews, asking for a preview of what the form currently holds.
  # Finds or creates the row for (user, profile_key, params_digest), starts a run
  # when it has no fresh result, and replaces the frame with its current state.
  def create
    found = locate_preview
    found = start_run(found) if needs_run?(found)
    render_frame(found)
  end

  # PATCH /feed_previews/:id, the explicit refresh. The row already holds the
  # source and selections, so a re-run needs nothing but its id.
  def update
    preview.restart!
    render_frame(preview)
  end

  helper_method :state_partial

  private

  def guard_preview
    return render_cleared if source_blank? || !FeedProfile.exists?(profile_key)
    return render_credential_gate if needs_credential_gate?

    render_cleared if invalid_ai_selection?
  end

  # Server-side backstop for the Stimulus button: an AI preview needs owned,
  # active AI and search credentials plus a listed or previously selected model.
  def invalid_ai_selection?
    return false unless FeedProfile.depends_on_ai?(profile_key)

    ai_credential.blank? || search_credential.blank? || !available_ai_model?
  end

  def available_ai_model?
    return false if ai_model.blank?
    return true if ai_credential.supports_model?(ai_model)
    return true if preview && preview.ai_model == ai_model

    Current.user.feeds.exists?(ai_credential: ai_credential, ai_model: ai_model)
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
      ai_credential_id: ai_credential&.id,
      ai_model: ai_model,
      search_credential_id: search_credential&.id
    )
  end

  # Resolve only from the user's own active credentials, so forged ids can't
  # borrow another user's provider keys.
  def ai_credential
    return @ai_credential if defined?(@ai_credential)

    requested = preview ? preview.ai_credential_id : params[:ai_credential_id]
    @ai_credential = Current.user.ai_credentials.active.find_by(id: requested)
  end

  def search_credential
    return @search_credential if defined?(@search_credential)

    @search_credential =
      if preview
        Current.user.search_credentials.active.find_by(id: preview.search_credential_id)
      else
        resolve_search_credential(profile_key, params[:search_credential_id])
      end
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
    @ai_model ||= preview ? preview.ai_model : params[:ai_model].presence
  end

  def locate_preview
    previews.find_or_initialize_by(feed_profile_key: profile_key, params_digest: digest)
  end

  def needs_run?(preview)
    preview.new_record? || stale_ready?(preview)
  end

  # Start a fresh run and return the persisted row. If a concurrent request
  # already inserted this (user, profile, source) row, adopt the winner's row
  # rather than enqueuing a duplicate job.
  def start_run(preview)
    preview.assign_attributes(
      params: preview_params,
      ai_credential_id: ai_credential&.id,
      ai_model: ai_model,
      search_credential_id: search_credential&.id
    )
    preview.restart!
  rescue ActiveRecord::RecordNotUnique
    previews.find_by!(feed_profile_key: profile_key, params_digest: digest)
  end

  def profile_key
    @profile_key ||= preview ? preview.feed_profile_key : params[:profile_key].to_s
  end

  # New previews keep only the profile's declared keys and cast them to the
  # declared types, matching the params a saved feed would use.
  def preview_params
    @preview_params ||=
      if preview
        preview.params
      else
        raw = params[:params]
        hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : (raw || {})
        declared = FeedProfile.parameter_keys_for(profile_key) || []
        FeedProfile.cast_params(profile_key, hash.deep_stringify_keys.slice(*declared))
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
