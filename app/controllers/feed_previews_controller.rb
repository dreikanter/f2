class FeedPreviewsController < ApplicationController
  before_action :require_authentication

  def create
    feed_profile_name = params[:feed_profile_name]

    unless feed_profile_name.present?
      redirect_back(fallback_location: feeds_path, alert: "Feed profile name is required.")
      return
    end

    feed_profile = FeedProfile.find_by(name: feed_profile_name)
    unless feed_profile
      redirect_back(fallback_location: feeds_path, alert: "Feed profile not found.")
      return
    end

    # Find or create feed preview (model validation will handle URL validation)
    feed_preview = FeedPreview.find_or_create(
      url: params[:url],
      feed_profile: feed_profile,
      user: Current.user
    )

    # Atomically enqueue job if needed (protects against race conditions)
    feed_preview.enqueue_job_if_needed!

    redirect_to feed_preview_path(feed_preview)
  rescue ActiveRecord::RecordInvalid
    redirect_back(fallback_location: feeds_path, alert: "Invalid URL provided.")
  rescue => e
    Rails.logger.error "FeedPreview creation failed: #{e.message}"
    redirect_back(fallback_location: feeds_path, alert: "Failed to create preview.")
  end

  def show
    @feed_preview = FeedPreview.find(params[:id])
    respond_to do |format|
      format.html
      format.turbo_stream do
        if @feed_preview.ready?
          render turbo_stream: turbo_stream.replace("preview-status",
            partial: "feed_previews/completed_status", locals: { feed_preview: @feed_preview })
        else
          render turbo_stream: turbo_stream.replace("preview-status",
            partial: "feed_previews/processing_status", locals: { feed_preview: @feed_preview })
        end
      end
    end
  end

  def update
    old_preview = FeedPreview.find(params[:id])
    old_preview.destroy

    # Create new preview with same parameters as old one
    feed_preview = FeedPreview.find_or_create(
      url: old_preview.url,
      feed_profile: old_preview.feed_profile,
      user: Current.user
    )

    feed_preview.enqueue_job_if_needed!

    redirect_to feed_preview_path(feed_preview), notice: "Preview refresh started."
  rescue ActiveRecord::RecordInvalid
    redirect_back(fallback_location: feeds_path, alert: "Invalid URL provided.")
  rescue => e
    Rails.logger.error "FeedPreview refresh failed: #{e.message}"
    redirect_back(fallback_location: feeds_path, alert: "Failed to refresh preview.")
  end

end
