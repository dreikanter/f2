# Keeps interactive state changes and their events in one transaction.
# System-driven disables emit their own events; controllers enqueue refreshes.
module FeedStateTransitions
  extend ActiveSupport::Concern

  private

  def enable_feed(feed, reset_schedule: false)
    feed.transaction do
      next false unless feed.enable

      record_feed_enabled(feed)
      feed.reset_schedule! if reset_schedule
      true
    end
  end

  def disable_feed(feed)
    feed.transaction do
      next false unless feed.disable

      record_feed_disabled(feed)
      true
    end
  end

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
      user: feed.user
    )
  end
end
