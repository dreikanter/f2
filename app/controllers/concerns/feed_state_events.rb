# Logs the feed_enabled/feed_disabled event when a controller flips a feed's
# state. These transitions are interactive, so they're recorded here rather
# than in a model callback; system-driven disables (token/credential failures,
# repeated refresh errors) emit their own events.
module FeedStateEvents
  extend ActiveSupport::Concern

  private

  def record_feed_enabled(feed)
    record_feed_state_event(feed, "feed_enabled", :info)
  end

  def record_feed_disabled(feed)
    record_feed_state_event(feed, "feed_disabled", :warning)
  end

  def record_feed_state_event(feed, type, level)
    Event.create!(
      type: type,
      level: level,
      subject: feed,
      user: feed.user,
      message: ""
    )
  end
end
