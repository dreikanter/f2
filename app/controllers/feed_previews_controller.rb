class FeedPreviewsController < ApplicationController
  before_action :require_authentication

  # Maps each FeedPreview status to the pane partial that renders it. `fetch`
  # makes an unexpected status fail loudly rather than silently fall through.
  STATE_PARTIALS = {
    "pending" => "processing",
    "processing" => "processing",
    "ready" => "ready",
    "failed" => "failed"
  }.freeze

  # GET /preview?profile_key=…&params[…]=…
  # Workhorse for the lazy turbo-frame and polling: find-or-create the row for
  # (user, profile_key, params_digest), enqueue when it has no fresh result,
  # and render the current state.
  def show
    return render_cleared if source_blank?
    return render_cleared unless FeedProfile.exists?(profile_key)
    return render_credential_gate if needs_credential_gate?

    locate_preview
    if @preview.new_record? || @preview.failed? || stale_ready?(@preview)
      start_run(@preview)
    end
    render_state(@preview)
  end

  # POST /preview — explicit refresh: always start a fresh run.
  def create
    return render_cleared if source_blank?
    return render_cleared unless FeedProfile.exists?(profile_key)
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
    @digest ||= FeedPreview.digest_for(profile_key, preview_params)
  end

  def locate_preview
    @preview = previews.find_or_initialize_by(feed_profile_key: profile_key, params_digest: digest)
  end

  def start_run(preview)
    preview.assign_attributes(params: preview_params, status: :pending, data: nil, ready_at: nil, run_id: SecureRandom.uuid)
    begin
      preview.save!
    rescue ActiveRecord::RecordNotUnique
      # Another concurrent request already inserted this row — load the winner's
      # row and render its state without enqueuing a second job.
      @preview = previews.find_by!(feed_profile_key: profile_key, params_digest: digest)
      return
    end
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

  def stale_ready?(preview)
    preview.ready? && preview.ready_at.present? && preview.ready_at < Feed::ENABLE_PREVIEW_WINDOW.ago
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
