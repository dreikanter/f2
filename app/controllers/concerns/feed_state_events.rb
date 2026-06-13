# Records the user-facing event when a controller flips a feed between the
# enabled and disabled states. These transitions are all interactive, so the
# events are logged here rather than via a model callback; system-driven
# disables (token/credential failures, repeated refresh errors) emit their own
# events at their own call sites.
module FeedStateEvents
  extend ActiveSupport::Concern

  private

  def record_feed_enabled(feed)
    record_feed_state_event(feed, "feed_enabled")
  end

  def record_feed_disabled(feed)
    record_feed_state_event(feed, "feed_disabled")
  end

  def record_feed_state_event(feed, type)
    Event.create!(type: type, level: :info, subject: feed, user: feed.user, message: "")
  end
end
