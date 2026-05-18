# Renders the live preview pane on the feed creation / edit form.
#
# Backed by FeedPreviewService + FeedPreviewJob: cache hits render the
# preview synchronously, cache misses enqueue the async job and return a
# loading partial whose polling controller picks the result up from the
# cache.
class Feeds::PreviewsController < ApplicationController
  before_action :require_authentication

  DRAFT_FEED_ID = "draft"

  def show
    @partial, @partial_locals =
      case cached_preview
      when FeedPreviewService::Preview
        [:preview, { preview: cached_preview, refresh_url: action_url }]
      when Hash
        [:preview_failed, { failure: cached_preview, retry_url: action_url }]
      else
        enqueue_preview_job
        [:preview_loading, { poll_url: action_url(format: :turbo_stream), cancel_url: cancel_url }]
      end

    render_view_state
  end

  def create
    Rails.cache.delete(cache_key)
    enqueue_preview_job(refresh: true)

    @partial = :preview_loading
    @partial_locals = { poll_url: action_url(format: :turbo_stream), cancel_url: cancel_url }

    render_view_state
  end

  def destroy
    Rails.cache.delete(cache_key)

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("feed-preview", "") }
      format.html { head :no_content }
    end
  end

  private

  def render_view_state
    respond_to do |format|
      format.html { render "feeds/previews/show" }
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "feed-preview",
          partial: "feeds/#{@partial}",
          locals: @partial_locals
        )
      end
    end
  end

  def cached_preview
    return @cached_preview if defined?(@cached_preview)

    @cached_preview = Rails.cache.read(cache_key)
  end

  def enqueue_preview_job(refresh: false)
    FeedPreviewJob.perform_later(
      "user_id" => Current.user.id,
      "profile_key" => profile_key,
      "params" => preview_params,
      "cache_key" => cache_key,
      "llm_credential_id" => nil,
      "limit" => 5,
      "refresh" => refresh
    )
  end

  def cache_key
    @cache_key ||= "preview:#{cache_namespace}:#{profile_key}:#{params_digest}"
  end

  def cache_namespace
    draft? ? "draft:#{Current.user.id}" : "feed:#{feed.id}"
  end

  def params_digest
    canonical = preview_params.deep_stringify_keys.sort.to_h.to_json
    Digest::SHA256.hexdigest(canonical)
  end

  def preview_params
    return @preview_params if defined?(@preview_params)

    raw = params[:params]
    @preview_params =
      case raw
      when ActionController::Parameters then raw.to_unsafe_h
      when Hash then raw
      else {}
      end
  end

  def profile_key
    @profile_key ||= params[:profile_key].to_s
  end

  def feed
    @feed ||= Current.user.feeds.find(params[:feed_id])
  end

  def draft?
    params[:feed_id] == DRAFT_FEED_ID
  end

  def action_url(format: nil)
    feed_id_segment = draft? ? DRAFT_FEED_ID : feed.id
    feed_live_preview_path(
      feed_id_segment,
      profile_key: profile_key,
      params: preview_params,
      format: format
    )
  end

  def cancel_url
    return nil unless draft?

    source = preview_params["url"].presence
    source ? feed_details_path(url: source) : nil
  end
end
