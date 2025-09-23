class FeedPreviewsController < ApplicationController
  before_action :require_authentication

  def create
    feed_profile = FeedProfile.find_by!(name: params.require(:feed_profile_name))

    feed_preview = FeedPreview.find_or_create(
      url: params[:url],
      feed_profile: feed_profile,
      user: Current.user
    )

    feed_preview.enqueue_job_if_needed!

    redirect_to feed_preview_path(feed_preview)
  rescue ActiveRecord::RecordInvalid
    redirect_back(fallback_location: feeds_path, alert: "Invalid URL provided.")
  end

  def show
    @feed_preview = FeedPreview.find(params[:id])
    respond_to do |format|
      format.html
      format.turbo_stream do
        status_partial = @feed_preview.ready? ? "completed_status" : "processing_status"
        render turbo_stream: turbo_stream.replace("preview-status",
          partial: "feed_previews/#{status_partial}", locals: { feed_preview: @feed_preview })
      end
    end
  end

  def update
    feed_preview = FeedPreview.find(params[:id])

    feed_preview = FeedPreview.find_or_create(
      url: feed_preview.url,
      feed_profile: feed_preview.feed_profile,
      user: Current.user
    )

    feed_preview.enqueue_job_if_needed!

    redirect_to feed_preview_path(feed_preview), notice: "Preview refresh started."
  rescue ActiveRecord::RecordInvalid
    redirect_back(fallback_location: feeds_path, alert: "Invalid URL provided.")
  end

end
