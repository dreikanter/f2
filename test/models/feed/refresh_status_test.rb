require "test_helper"

class Feed::RefreshStatusTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed)
  end

  def refresh_event(status)
    create(:event, subject: feed, type: "feed_refresh", metadata: { status: status })
  end

  test "#refreshing? should be false without a refresh request or event" do
    assert_not Feed::RefreshStatus.new(feed: feed).refreshing?
  end

  test "#refreshing? should be true immediately after a request" do
    refresh_event("completed")

    assert Feed::RefreshStatus.new(feed: feed, requested: true).refreshing?
  end

  test "#refreshing? should be true while the worker runs" do
    refresh_event("started")

    assert Feed::RefreshStatus.new(feed: feed).refreshing?
  end

  test "#refreshing? should wait for the first event after an empty redirect" do
    cursor = Feed::RefreshStatus.new(feed: feed).cursor

    assert Feed::RefreshStatus.new(feed: feed, pending_after: cursor).refreshing?
    refresh_event("completed")
    assert_not Feed::RefreshStatus.new(feed: feed, pending_after: cursor).refreshing?
  end

  test "#refreshing? should stop waiting when a newer refresh settles" do
    %w[completed failed].each do |outcome|
      old = refresh_event("completed")
      assert Feed::RefreshStatus.new(feed: feed, pending_after: old.id).refreshing?

      terminal = refresh_event(outcome)
      status = Feed::RefreshStatus.new(feed: feed, pending_after: old.id)

      assert_not status.refreshing?
      assert_equal terminal, status.event
    end
  end

  test "#event should ignore unrelated and expired events" do
    completed = refresh_event("completed")
    create(:event, subject: feed, type: "feed_refresh", expires_at: 1.minute.ago,
                   metadata: { status: "started" })
    create(:event, subject: feed, type: "feed_disabled")

    status = Feed::RefreshStatus.new(feed: feed)

    assert_equal completed, status.event
    assert_not status.refreshing?
  end
end
