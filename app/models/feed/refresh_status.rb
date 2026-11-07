class Feed::RefreshStatus
  EMPTY_CURSOR = "none".freeze

  attr_reader :feed, :event

  def initialize(feed:, pending_after: nil, requested: false)
    @feed = feed
    @event = feed.events.user_relevant.where(type: "feed_refresh").recent.first
    @pending_after = pending_after
    @requested = requested
  end

  def cursor
    event&.id || EMPTY_CURSOR
  end

  def refreshing?
    @requested || awaiting_start? || running?
  end

  private

  def running?
    event.present? && event.metadata["status"] == "started"
  end

  # An HTML redirect can arrive before the worker records its started event.
  def awaiting_start?
    @pending_after.present? && @pending_after == cursor
  end
end
