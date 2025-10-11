class FeedPreviewsController < ApplicationController
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
          streams << turbo_stream.replace("preview-status",
            partial: "feed_previews/#{partial_name}", locals: { feed_preview: @feed_preview })
        end

        # Update the header actions to show/hide refresh button
        streams << turbo_stream.replace("header-actions",
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
      feed_profile_key: existing_preview.feed_profile_key
    )
    redirect_to feed_preview_path(feed_preview)
  rescue ActiveRecord::RecordNotFound
    redirect_to feeds_path, alert: "Preview not found."
  rescue ActiveRecord::RecordInvalid
    redirect_back(fallback_location: feeds_path, alert: "Invalid URL provided.")
  end

  private

  def create_and_enqueue_preview(url:, feed_profile_key:)
    feed_preview = nil

    FeedPreview.transaction do
      # Delete any existing preview for this URL and feed profile
      FeedPreview.for_cache_key(url, feed_profile_key).where(user: Current.user).destroy_all

      # Create a new preview and start processing
      feed_preview = FeedPreview.create!(
        url: url,
        feed_profile_key: feed_profile_key,
        user_id: Current.user.id,
        status: :pending
      )

      FeedPreviewJob.perform_later(feed_preview.id)
    end

    feed_preview
  end
end
