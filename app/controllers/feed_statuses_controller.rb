class FeedStatusesController < ApplicationController
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
    result = Feed::StateTransition.new(feed).enable

    if result.success?
      refresh_requested = result.changed? && feed.scheduled?
      @refresh_status = Feed::RefreshStatus.new(feed: feed, requested: refresh_requested)
      FeedRefreshJob.perform_later(feed.id) if refresh_requested
      respond_with_status(feed, success: "Feed enabled.", refresh_requested: refresh_requested)
    else
      respond_with_status(feed, alert: cannot_enable_alert(feed))
    end
  end

  # The missing parts name what to fix. The enabled-state validators are a
  # separate rule set, so their messages are the fallback when the feed looks
  # ready but a validator still refuses.
  def cannot_enable_alert(feed)
    missing_parts = feed.missing_enablement_parts
    return "Cannot enable feed: missing #{missing_parts.join(' and ')}." if missing_parts.any?

    "Cannot enable feed: #{feed.errors.full_messages.join('; ')}."
  end

  def disable(feed)
    result = Feed::StateTransition.new(feed).disable

    if result.success?
      respond_with_status(feed, success: "Feed disabled.")
    else
      respond_with_status(feed, alert: "Cannot disable feed: #{feed.errors.full_messages.join('; ')}.")
    end
  end

  # HTML clients redirect to the feed page; Turbo clients get a stream that
  # re-renders the feed heading (feed page) or the feed card (feeds index).
  def respond_with_status(feed, success: nil, alert: nil, refresh_requested: false)
    @refresh_status ||= Feed::RefreshStatus.new(feed: feed)

    respond_to do |format|
      format.html do
        redirect_to feed_path(feed, refresh_after: (@refresh_status.cursor if refresh_requested)),
                    success: success, alert: alert
      end
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
