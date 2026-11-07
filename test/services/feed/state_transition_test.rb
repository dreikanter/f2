require "test_helper"

class Feed::StateTransitionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "#enable should commit the state, schedule, and event without enqueuing a refresh" do
    feed = create(:feed, :disabled)
    result = nil

    assert_no_enqueued_jobs(only: FeedRefreshJob) do
      result = Feed::StateTransition.new(feed).enable
    end

    assert result.success?
    assert result.changed?
    assert_predicate feed.reload, :enabled?
    assert_not_nil feed.feed_schedule
    event = feed.events.find_by!(type: "feed_enabled")
    assert_equal "info", event.level
    assert_equal feed.user, event.user
  end

  test "#enable should reload stale state and avoid duplicate events and schedules" do
    feed = create(:feed, :disabled)
    stale = Feed.find(feed.id)
    Feed::StateTransition.new(feed).enable

    assert_no_difference ["Event.count", "FeedSchedule.count"] do
      result = Feed::StateTransition.new(stale).enable

      assert result.success?
      assert_not result.changed?
    end

    assert_predicate stale, :enabled?
  end

  test "#enable should preserve validation errors and leave invalid feeds disabled" do
    feed = create(:feed, :disabled, target_group: nil)
    result = nil

    assert_no_difference ["Event.count", "FeedSchedule.count"] do
      result = Feed::StateTransition.new(feed).enable
    end

    assert_not result.success?
    assert_not result.changed?
    assert feed.errors.of_kind?(:target_group, :blank)
    assert_predicate feed.reload, :disabled?
  end

  test "#enable should roll back the state and schedule when event recording fails" do
    feed = create(:feed, :disabled)
    fail_event = ->(**) { raise ActiveRecord::RecordInvalid.new(Event.new) }

    assert_no_difference ["Event.count", "FeedSchedule.count"] do
      Event.stub(:create!, fail_event) do
        assert_raises(ActiveRecord::RecordInvalid) { Feed::StateTransition.new(feed).enable }
      end
    end

    assert_predicate feed.reload, :disabled?
  end

  test "#enable should reset the schedule in the same transaction as the state and event" do
    feed = create(:feed, :disabled, :with_schedule)
    feed.feed_schedule.update!(next_run_at: 12.hours.from_now)

    freeze_time do
      result = Feed::StateTransition.new(feed).enable(reset_schedule: true)

      assert result.success?
      assert result.changed?
      assert_equal Time.current, feed.feed_schedule.reload.next_run_at
    end
  end

  test "#enable should roll back the state and event when schedule reset fails" do
    feed = create(:feed, :disabled, :with_schedule)
    next_run_at = feed.feed_schedule.next_run_at
    fail_reset = -> { raise ActiveRecord::RecordInvalid.new(feed.feed_schedule) }

    assert_no_difference "Event.count" do
      feed.stub(:reset_schedule!, fail_reset) do
        assert_raises(ActiveRecord::RecordInvalid) do
          Feed::StateTransition.new(feed).enable(reset_schedule: true)
        end
      end
    end

    assert_predicate feed.reload, :disabled?
    assert_equal next_run_at, feed.feed_schedule.reload.next_run_at
  end

  test "#enable should not create a schedule for webhook feeds" do
    feed = create(:feed, :webhook, :draft)
    result = Feed::StateTransition.new(feed).enable

    assert result.success?
    assert result.changed?
    assert_predicate feed.reload, :enabled?
    assert_nil feed.feed_schedule
  end

  test "#disable should commit the state and a warning event" do
    feed = create(:feed, :enabled)
    result = Feed::StateTransition.new(feed).disable

    assert result.success?
    assert result.changed?
    assert_predicate feed.reload, :disabled?
    assert_equal "warning", feed.events.find_by!(type: "feed_disabled").level
  end

  test "#disable should reload stale state and avoid duplicate events" do
    feed = create(:feed, :enabled)
    stale = Feed.find(feed.id)
    Feed::StateTransition.new(feed).disable

    assert_no_difference "Event.count" do
      result = Feed::StateTransition.new(stale).disable

      assert result.success?
      assert_not result.changed?
    end

    assert_predicate stale, :disabled?
  end
end
