class FeedPreviewsController < ApplicationController
  include StatePolling

  before_action :require_authentication
  before_action :guard_preview, only: %i[show create]

  # Maps each FeedPreview status to the pane partial that renders it. `fetch`
  # makes an unexpected status fail loudly rather than silently fall through.
  STATE_PARTIALS = {
    "pending" => "processing",
    "processing" => "processing",
    "ready" => "ready",
    "failed" => "failed"
  }.freeze

  # GET /feed_preview?profile_key=…&params[…]=…
  # Workhorse for the lazy turbo-frame and polling: find or create the row for
  # (user, profile_key, params_digest), start a run when it has no fresh result,
  # and render the current state.
  def show
    preview = locate_preview
    preview = start_run(preview) if needs_run?(preview)
    preview.timeout! if (preview.pending? || preview.processing?) && preview.updated_at < polling_timeout.ago
    render_state(preview, inert_while_running: true)
  end

  # POST /feed_preview — explicit refresh: always start a fresh run. Renders the
  # processing pane (never inert) so the refresh shows the spinner restarting.
  def create
    render_state(start_run(locate_preview))
  end

  private

  # Shared guard for show/create: clear the pane for a blank or unknown source,
  # or show the credential gate for an AI profile without an active credential.
  def guard_preview
    return render_cleared if source_blank? || !FeedProfile.exists?(profile_key)

    render_credential_gate if needs_credential_gate?
  end

  def previews
    Current.user.feed_previews
  end

  def digest
    @digest ||= FeedPreview.digest_for(profile_key, preview_params)
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
    preview.update!(params: preview_params, status: :pending, data: nil, ready_at: nil, run_id: SecureRandom.uuid)
    FeedPreviewJob.perform_later(preview.id, preview.run_id)
    preview
  rescue ActiveRecord::RecordNotUnique
    previews.find_by!(feed_profile_key: profile_key, params_digest: digest)
  end

  def profile_key
    @profile_key ||= params[:profile_key].to_s
  end

  def preview_params
    @preview_params ||= begin
      raw = params[:params]
      hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : (raw || {})
      hash.deep_stringify_keys
    end
  end

  def stale_ready?(preview)
    preview.ready? && preview.ready_at.present? && preview.ready_at < Feed::PREVIEW_FRESHNESS_WINDOW.ago
  end

  def source_blank?
    shape = FeedProfile[profile_key]&.dig(:input_shape)
    key = shape ? shape.to_s : "url"
    preview_params[key].to_s.strip.blank?
  end

  def needs_credential_gate?
    return false unless FeedProfile.exists?(profile_key)
    return false unless FeedProfile.depends_on_ai?(profile_key)

    !Current.user.ai_credentials.active.exists?
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
    gate = { partial: "feed_previews/credential_gate", locals: { profile_key: profile_key } }
    respond_to do |format|
      format.html do
        body = helpers.turbo_frame_tag("feed-preview") { render_to_string(gate).html_safe }
        render html: body, layout: false
      end
      format.turbo_stream { render turbo_stream: turbo_stream.update("feed-preview", **gate) }
    end
  end
end
