class FeedStatusesController < ApplicationController
  include FeedHelper

  def update
    @feed = load_feed

    case status
    when "enabled" then enable(@feed)
    when "disabled" then disable(@feed)
    else raise "Unsupported status: #{status.inspect}"
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to feeds_path, alert: "Feed not found."
  rescue ActiveRecord::StaleObjectError
    redirect_to @feed, alert: "Feed was modified by another user. Please try again."
  end

  private

  def enable(feed)
    feed.with_lock do
      if feed.can_be_enabled?
        feed.enabled!
        respond_with_status(feed, success: "Feed enabled.")
      else
        missing_parts = feed_missing_enablement_parts(feed)
        respond_with_status(feed, alert: "Cannot enable feed: missing #{missing_parts.join(' and ')}.")
      end
    end
  end

  def disable(feed)
    feed.with_lock do
      feed.disabled!
      respond_with_status(feed, success: "Feed disabled.")
    end
  end

  # HTML clients get a redirect to the feed page; Turbo clients get a stream
  # that re-renders the feed heading (feed page) or the feed card (feeds index)
  # in place, with the flash surfaced as a toast.
  def respond_with_status(feed, success: nil, alert: nil)
    respond_to do |format|
      format.html { redirect_to feed, success: success, alert: alert }
      format.turbo_stream do
        flash.now[:success] = success if success
        flash.now[:alert] = alert if alert
        render :update
      end
    end
  end

  def status
    @status ||= params[:status]
  end

  def load_feed
    Current.user.feeds.find(params[:feed_id])
  end
end
