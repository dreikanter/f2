class FeedStatusesController < ApplicationController
  include FeedHelper

  def update
    feed = load_feed

    case status
    when "enabled" then enable(feed)
    when "disabled" then disable(feed)
    else raise "Unsupported status: #{status.inspect}"
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to feeds_path, alert: "Feed not found."
  rescue ActiveRecord::StaleObjectError
    redirect_to feed, alert: "Feed was modified by another user. Please try again."
  end

  private

  def enable(feed)
    feed.with_lock do
      if feed.can_be_enabled?
        feed.enabled!
        redirect_to feed, notice: "Feed enabled."
      else
        missing_parts = feed_missing_enablement_parts(feed)
        redirect_to feed, alert: "Cannot enable feed: missing #{missing_parts.join(' and ')}."
      end
    end
  end

  def disable(feed)
    feed.with_lock do
      feed.disabled!
      redirect_to feed, notice: "Feed disabled."
    end
  end

  def status
    @status ||= params[:status]
  end

  def load_feed
    Current.user.feeds.find(params[:feed_id])
  end
end
