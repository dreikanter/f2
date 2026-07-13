class FeedStatusesController < ApplicationController
  include FeedHelper
  include FeedStateEvents

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
      if feed.can_be_enabled? && feed.enable
        record_feed_enabled(feed)
        respond_with_status(feed, success: "Feed enabled.")
      else
        respond_with_status(feed, alert: cannot_enable_alert(feed))
      end
    end
  end

  # can_be_enabled? mirrors the enabled-state validators, but they are separate
  # rule sets: name the missing parts when we know them, and fall back to the
  # validator messages for any residual drift instead of raising.
  def cannot_enable_alert(feed)
    missing_parts = feed_missing_enablement_parts(feed)
    return "Cannot enable feed: missing #{missing_parts.join(' and ')}." if missing_parts.any?

    "Cannot enable feed: #{feed.errors.full_messages.join('; ')}."
  end

  def disable(feed)
    feed.with_lock do
      if feed.disable
        record_feed_disabled(feed)
        respond_with_status(feed, success: "Feed disabled.")
      else
        respond_with_status(feed, alert: "Cannot disable feed: #{feed.errors.full_messages.join('; ')}.")
      end
    end
  end

  # HTML clients redirect to the feed page; Turbo clients get a stream that
  # re-renders the feed heading (feed page) or the feed card (feeds index).
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
