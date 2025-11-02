class FeedPreviewsController < ApplicationController
  layout "tailwind"
  before_action :require_authentication

  STATUS_PARTIALS = {
    "ready" => "completed_status",
    "pending" => "processing_status",
    "processing" => "processing_status",
    "failed" => "failed_status"
  }.freeze

  def create
    feed_profile_key = params[:feed_profile_key]

    unless FeedProfile.exists?(feed_profile_key)
      redirect_back(fallback_location: feeds_path, alert: "Feed profile not found.")
      return
    end

    feed_preview = create_and_enqueue_preview(url: params[:url], feed_profile_key: feed_profile_key)
    redirect_to feed_preview_path(feed_preview)
  rescue ActiveRecord::RecordInvalid
    redirect_back(fallback_location: feeds_path, alert: "Invalid URL provided.")
  end

  def show
    @feed_preview = FeedPreview.find(params[:id])

    respond_to do |format|
      format.html
      format.turbo_stream do
        streams = []

        # Update the status section
        if partial_name = STATUS_PARTIALS[@feed_preview.status]
        streams << turbo_stream.update("preview-status",
          partial: "feed_previews/#{partial_name}", locals: { feed_preview: @feed_preview })
        end

        # Update the header actions to show/hide refresh button
        streams << turbo_stream.update("header-actions",
          partial: "feed_previews/header_actions", locals: { feed_preview: @feed_preview })

        render turbo_stream: streams
      end
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to feeds_path, alert: "Preview not found."
  end

  def update
    existing_preview = FeedPreview.find(params[:id])

    feed_preview = create_and_enqueue_preview(
      url: existing_preview.url,
      feed_profile_key: existing_preview.feed_profile_key,
      force_refresh: true
    )

    redirect_to feed_preview_path(feed_preview)
  rescue ActiveRecord::RecordNotFound
    redirect_to feeds_path, alert: "Preview not found."
  rescue ActiveRecord::RecordInvalid
    redirect_back(fallback_location: feeds_path, alert: "Invalid URL provided.")
  end

  private

  def create_and_enqueue_preview(url:, feed_profile_key:, force_refresh: false)
    existing_preview = FeedPreview.for_cache_key(url, feed_profile_key).where(user: Current.user).first

    unless existing_preview
      preview = create_new_preview(url, feed_profile_key)
      enqueue_preview_job(preview)
      return preview
    end

    if force_refresh
      existing_preview.update!(status: :pending, data: nil)
      enqueue_preview_job(existing_preview)
      return existing_preview
    end

    if existing_preview.failed?
      existing_preview.update!(status: :pending)
      enqueue_preview_job(existing_preview)
    end

    existing_preview
  end

  def create_new_preview(url, feed_profile_key)
    FeedPreview.create!(
      url: url,
      feed_profile_key: feed_profile_key,
      user_id: Current.user.id,
      status: :pending
    )
  end

  def enqueue_preview_job(preview)
    FeedPreviewJob.perform_later(preview.id)
  end
end
