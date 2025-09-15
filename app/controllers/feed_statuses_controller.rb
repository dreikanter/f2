class FeedStatusesController < ApplicationController
  include FeedHelper

  def update
    @feed = load_feed
    status = params[:status]

    case status
    when "enabled"
      Feed.transaction do
        @feed.lock!
        if @feed.can_be_enabled?
          @feed.update!(state: :enabled)
          redirect_to @feed, notice: "Feed was successfully enabled."
        else
          missing_parts = feed_missing_enablement_parts(@feed)
          redirect_to @feed, alert: "Cannot enable feed: missing #{missing_parts.join(' and ')}."
        end
      end
    when "disabled"
      Feed.transaction do
        @feed.lock!
        @feed.update!(state: :disabled)
        redirect_to @feed, notice: "Feed was successfully disabled."
      end
    else
      redirect_to @feed, alert: "Invalid status parameter."
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to feeds_path, alert: "Feed not found."
  rescue ActiveRecord::StaleObjectError
    redirect_to @feed, alert: "Feed was modified by another user. Please try again."
  end

  private

  def load_feed
    Current.user.feeds.find(params[:feed_id])
  end
end
