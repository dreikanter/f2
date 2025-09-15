class FeedStatusesController < ApplicationController
  include FeedHelper

  def update
    @feed = load_feed
    status = params[:status]

    case status
    when "enabled"
      if @feed.access_token&.active? && @feed.target_group.present?
        @feed.update!(state: :enabled)
        redirect_to @feed, notice: "Feed was successfully enabled."
      else
        missing_parts = feed_missing_enablement_parts(@feed)
        redirect_to @feed, alert: "Cannot enable feed: missing #{missing_parts.join(' and ')}."
      end
    when "disabled"
      @feed.update!(state: :disabled)
      redirect_to @feed, notice: "Feed was successfully disabled."
    else
      redirect_to @feed, alert: "Invalid status parameter."
    end
  end

  private

  def load_feed
    Current.user.feeds.find(params[:feed_id])
  end
end
