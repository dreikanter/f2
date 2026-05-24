class FeedPreviewsController < ApplicationController
  before_action :require_authentication

  # GET /preview?profile_key=…&params[…]=…
  # Workhorse for the lazy turbo-frame and polling: find-or-create the row for
  # (user, profile_key, params_digest), enqueue when it has no fresh result,
  # and render the current state.
  def show
    return render_cleared if source_blank?
    return render_credential_gate if needs_credential_gate?

    preview = locate_preview
    if preview.new_record? || preview.failed?
      start_run(preview)
    end
    render_state(preview)
  end

  # POST /preview — explicit refresh: always start a fresh run.
  def create
    return render_cleared if source_blank?
    return render_credential_gate if needs_credential_gate?

    start_run(locate_preview)
    render_state(@preview)
  end

  # DELETE /preview — clear the pane (and drop the row).
  def destroy
    previews.where(feed_profile_key: profile_key, params_digest: digest).destroy_all
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("feed-preview", "") }
      format.html { head :no_content }
    end
  end

  private

  def previews
    Current.user.feed_previews
  end

  def digest
    @digest ||= FeedPreview.digest_for(preview_params)
  end

  def locate_preview
    @preview = previews.find_or_initialize_by(feed_profile_key: profile_key, params_digest: digest)
  end

  def start_run(preview)
    preview.update!(params: preview_params, status: :pending, data: nil, ready_at: nil, run_id: SecureRandom.uuid)
    FeedPreviewJob.perform_later(preview.id, preview.run_id)
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

  def source_blank?
    shape = FeedProfile[profile_key]&.dig(:input_shape)
    key = shape ? shape.to_s : "url"
    preview_params[key].to_s.strip.blank?
  end

  def needs_credential_gate?
    return false unless FeedProfile.exists?(profile_key)
    return false unless FeedProfile.depends_on_ai?(profile_key)

    !Current.user.llm_credentials.active.exists?
  end

  def render_state(preview)
    respond_to do |format|
      format.html { render :show, locals: { preview: preview } }
      format.turbo_stream { render turbo_stream: turbo_stream.update("feed-preview", state_partial(preview)) }
    end
  end

  def state_partial(preview)
    case preview.status
    when "ready" then { partial: "feed_previews/ready", locals: { preview: preview } }
    when "failed" then { partial: "feed_previews/failed", locals: { preview: preview } }
    else { partial: "feed_previews/processing", locals: { preview: preview } }
    end
  end

  def render_cleared
    respond_to do |format|
      format.html { head :no_content }
      format.turbo_stream { render turbo_stream: turbo_stream.update("feed-preview", "") }
    end
  end

  def render_credential_gate
    render turbo_stream: turbo_stream.update(
      "feed-preview",
      partial: "feed_previews/credential_gate",
      locals: { profile_key: profile_key }
    )
  end
end
