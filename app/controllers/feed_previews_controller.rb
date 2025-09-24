class FeedPreviewsController < ApplicationController
  before_action :require_authentication

  def create
    feed_profile = FeedProfile.find_by!(name: params.require(:feed_profile_name))

    find_or_create_and_enqueue(
      url: params[:url],
      feed_profile: feed_profile
    )
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
    existing_preview = FeedPreview.find(params[:id])

    find_or_create_and_enqueue(
      url: existing_preview.url,
      feed_profile: existing_preview.feed_profile,
      notice: "Preview refresh started."
    )
  rescue ActiveRecord::RecordInvalid
    redirect_back(fallback_location: feeds_path, alert: "Invalid URL provided.")
  end

  private

  def find_or_create_and_enqueue(url:, feed_profile:, notice: nil)
    feed_preview = nil

    FeedPreview.transaction do
      feed_preview = FeedPreview.create_with(user: Current.user, status: :pending)
        .find_or_create_by(url: url, feed_profile: feed_profile)

      # Atomically enqueue job if preview is pending
      if feed_preview.pending?
        feed_preview.update!(status: :processing)
        FeedPreviewJob.perform_later(feed_preview.id)
      end
    end

    redirect_to feed_preview_path(feed_preview), notice: notice
  end
end
