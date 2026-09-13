class FeedPreviewsController < ApplicationController
  before_action :load_preview, only: %i[show update]

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
    render_state(preview)
  end

  def create
    request = FeedPreviewRequest.new(user: Current.user, attributes: preview_attributes)
    render_request(request.create)
  end

  def update
    request = FeedPreviewRequest.new(user: Current.user)
    render_request(request.refresh(preview))
  end

  helper_method :state_partial

  private

  attr_reader :preview

  def load_preview
    @preview = Current.user.feed_previews.find(params[:id])
  end

  def preview_attributes
    params.permit(:profile_key, :feed_id, :ai_credential_id, :ai_model, :search_credential_id)
          .to_h.merge(params: params[:params]&.to_unsafe_h || {})
  end

  def render_request(request)
    case request.error
    when :missing_ai_credentials
      render_credential_gate(request.profile_key)
    when :invalid_source, :invalid_ai_selection
      render_cleared
    else
      render_frame(request.preview)
    end
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

  def render_state(preview)
    respond_to do |format|
      format.html { render :show, locals: { preview: preview } }
      # Swap only the inner body so the polling host (rendered by `show`) stays
      # mounted across polls; ready/failed bodies carry `data-preview-done`,
      # which trips the poller's stop-condition. While a run is still in flight
      # the poll stays silent so the spinner keeps its animation instead of
      # being redrawn every cycle.
      format.turbo_stream do
        if preview.pending? || preview.processing?
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

  def render_credential_gate(profile_key)
    gate = {
      partial: "feed_previews/credential_gate",
      locals: {
        profile_key: profile_key,
        missing_ai_credentials: true
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
