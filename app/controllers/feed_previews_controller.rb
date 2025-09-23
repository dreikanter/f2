class FeedPreviewsController < ApplicationController
  before_action :set_feed_preview, only: [:show, :update]
  before_action :require_authentication

  def create
    @url = params[:url]

    # Validate URL format
    unless @url.present? && valid_url?(@url)
      redirect_back(fallback_location: feeds_path, alert: "Invalid URL provided.")
      return
    end

    # Handle feed profile from different sources
    @feed_profile = find_or_create_feed_profile

    unless @feed_profile
      redirect_back(fallback_location: feeds_path, alert: "Invalid feed configuration.")
      return
    end

    # Find or create feed preview
    @feed_preview = FeedPreview.find_or_create_for_preview(
      url: @url,
      feed_profile: @feed_profile,
      feed: params[:feed_id].present? ? Feed.find(params[:feed_id]) : nil
    )

    # Start background job if preview is pending
    if @feed_preview.pending?
      FeedPreviewJob.perform_later(@feed_preview.id)
    end

    redirect_to feed_preview_path(@feed_preview)
  rescue ActiveRecord::RecordNotFound
    redirect_back(fallback_location: feeds_path, alert: "Feed profile not found.")
  rescue => e
    Rails.logger.error "FeedPreview creation failed: #{e.message}"
    redirect_back(fallback_location: feeds_path, alert: "Failed to create preview.")
  end

  def show
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
    # Refresh the preview by creating a new one
    @feed_preview.destroy

    @new_preview = FeedPreview.find_or_create_for_preview(
      url: @feed_preview.url,
      feed_profile: @feed_preview.feed_profile,
      feed: @feed_preview.feed
    )

    FeedPreviewJob.perform_later(@new_preview.id)

    redirect_to feed_preview_path(@new_preview), notice: "Preview refresh started."
  rescue => e
    Rails.logger.error "FeedPreview refresh failed: #{e.message}"
    redirect_to feed_preview_path(@feed_preview), alert: "Failed to refresh preview."
  end

  private

  def set_feed_preview
    @feed_preview = FeedPreview.find(params[:id])
  end

  def find_or_create_feed_profile
    # If feed_profile_id is provided, use existing profile
    if params[:feed_profile_id].present?
      return FeedProfile.find(params[:feed_profile_id])
    end

    # If individual service attributes are provided, find or create a temporary profile
    if params[:loader].present? && params[:processor].present? && params[:normalizer].present?
      profile_name = "temp-#{params[:loader]}-#{params[:processor]}-#{params[:normalizer]}"

      # Try to find existing profile with same configuration
      existing_profile = FeedProfile.find_by(
        loader: params[:loader],
        processor: params[:processor],
        normalizer: params[:normalizer],
        user: Current.user
      )

      return existing_profile if existing_profile

      # Create temporary profile
      return FeedProfile.create!(
        name: profile_name,
        loader: params[:loader],
        processor: params[:processor],
        normalizer: params[:normalizer],
        user: Current.user
      )
    end

    nil
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to create feed profile: #{e.message}"
    nil
  end

  def valid_url?(url)
    uri = URI.parse(url.strip)
    %w[http https].include?(uri.scheme)
  rescue URI::InvalidURIError
    false
  end
end
