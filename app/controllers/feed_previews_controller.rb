class FeedPreviewsController < ApplicationController
  before_action :require_authentication

  def create
    feed_profile = FeedProfile.find_by!(name: params.require(:feed_profile_name))

    create_and_enqueue_preview(
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
        streams = []

        # Update the status section
        if @feed_preview.ready?
          streams << turbo_stream.replace("preview-status",
            partial: "feed_previews/completed_status", locals: { feed_preview: @feed_preview })
        elsif @feed_preview.pending? || @feed_preview.processing?
          streams << turbo_stream.replace("preview-status",
            partial: "feed_previews/processing_status", locals: { feed_preview: @feed_preview })
        elsif @feed_preview.failed?
          streams << turbo_stream.replace("preview-status",
            partial: "feed_previews/failed_status", locals: { feed_preview: @feed_preview })
        end

        # Update the header actions to show/hide refresh button
        streams << turbo_stream.replace("header-actions",
          partial: "feed_previews/header_actions", locals: { feed_preview: @feed_preview })

        render turbo_stream: streams
      end
    end
  end

  def update
    existing_preview = FeedPreview.find(params[:id])

    create_and_enqueue_preview(
      url: existing_preview.url,
      feed_profile: existing_preview.feed_profile
    )
  rescue ActiveRecord::RecordInvalid
    redirect_back(fallback_location: feeds_path, alert: "Invalid URL provided.")
  end

  private

  def create_and_enqueue_preview(url:, feed_profile:, notice: nil)
    feed_preview = nil

    FeedPreview.transaction do
      # Delete any existing preview for this URL and feed profile
      FeedPreview.where(url: url, feed_profile: feed_profile, user: Current.user).destroy_all

      # Create a new preview and start processing
      feed_preview = FeedPreview.create!(
        url: url,
        feed_profile: feed_profile,
        user_id: Current.user.id,
        status: :processing
      )

      FeedPreviewJob.perform_later(feed_preview.id)
    end

    redirect_to feed_preview_path(feed_preview), notice: notice
  end
end
