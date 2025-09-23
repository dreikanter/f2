class FeedPreviewsController < ApplicationController
  before_action :require_authentication

  def create
    url = params[:url]

    # Handle feed profile from different sources
    feed_profile = find_or_create_feed_profile

    unless feed_profile
      redirect_back(fallback_location: feeds_path, alert: "Invalid feed configuration.")
      return
    end

    # Find or create feed preview (model validation will handle URL validation)
    feed_preview = FeedPreview.find_or_create_for_preview(
      url: url,
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
    feed_preview = FeedPreview.find(params[:id])
    # Refresh the preview by creating a new one
    feed_preview.destroy

    new_preview = FeedPreview.find_or_create_for_preview(
      url: feed_preview.url,
      feed_profile: feed_preview.feed_profile,
      user: Current.user
    )

    new_preview.enqueue_job_if_needed!

    redirect_to feed_preview_path(new_preview), notice: "Preview refresh started."
  rescue ActiveRecord::RecordInvalid
    redirect_to feed_preview_path(feed_preview), alert: "Failed to refresh preview."
  rescue => e
    Rails.logger.error "FeedPreview refresh failed: #{e.message}"
    redirect_to feed_preview_path(feed_preview), alert: "Failed to refresh preview."
  end

  private

  def find_or_create_feed_profile
    # Profile name is required
    return nil unless params[:feed_profile_name].present?

    FeedProfile.find_by(name: params[:feed_profile_name], user: Current.user)
  end
end
