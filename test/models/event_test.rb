require "test_helper"

class EventTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed)
  end

  test "should create event with minimal attributes" do
    event = Event.create!(type: "test_event")

    assert_equal "test_event", event.type
    assert_equal "info", event.level
    assert_equal "", event.message
    assert_equal({}, event.metadata)
    assert_nil event.user
    assert_nil event.subject
    assert_nil event.expires_at
  end

  test "should create event with all attributes" do
    event = Event.create!(
      type: "feed_refresh_event",
      level: :error,
      message: "Feed refresh failed",
      metadata: { error: "timeout", retry_count: 3 },
      user: user,
      subject: feed,
      expires_at: 1.week.from_now
    )

    assert_equal "feed_refresh_event", event.type
    assert_equal "error", event.level
    assert_equal "Feed refresh failed", event.message
    assert_equal({ "error" => "timeout", "retry_count" => 3 }, event.metadata)
    assert_equal user, event.user
    assert_equal feed, event.subject
    assert event.expires_at.present?
  end

  test "should allow blank message" do
    event = Event.create!(type: "test_event", message: "")

    assert_equal "", event.message
  end

  test "should validate required fields" do
    event = Event.new

    assert_not event.valid?
    assert event.errors.of_kind?(:type, :blank)
  end

  test "should validate level enum" do
    event = Event.new(type: "test_event")

    assert event.valid?

    assert_raises(ArgumentError) do
      event.level = "invalid"
    end
  end

  test "should scope recent events" do
    old_event = Event.create!(type: "old_event", created_at: 2.days.ago)
    new_event = Event.create!(type: "new_event", created_at: 1.hour.ago)

    recent_events = Event.recent.limit(2)

    assert_equal [new_event, old_event], recent_events.to_a
  end

  test "should scope events for subject" do
    feed_event = Event.create!(type: "feed_event", subject: feed)
    user_event = Event.create!(type: "user_event", subject: user)

    feed_events = Event.for_subject(feed)

    assert_includes feed_events, feed_event
    assert_not_includes feed_events, user_event
  end

  test "should identify expired events" do
    expired_event = Event.create!(type: "expired_event", expires_at: 1.hour.ago)
    active_event = Event.create!(type: "active_event", expires_at: 1.hour.from_now)
    permanent_event = Event.create!(type: "permanent_event")

    assert expired_event.expired?
    assert_not active_event.expired?
    assert_not permanent_event.expired?
  end

  test "should scope expired events" do
    expired_event = Event.create!(type: "expired_event", expires_at: 1.hour.ago)
    active_event = Event.create!(type: "active_event", expires_at: 1.hour.from_now)
    permanent_event = Event.create!(type: "permanent_event")

    expired_events = Event.expired
    not_expired_events = Event.not_expired

    assert_includes expired_events, expired_event
    assert_not_includes expired_events, active_event
    assert_not_includes expired_events, permanent_event

    assert_not_includes not_expired_events, expired_event
    assert_includes not_expired_events, active_event
    assert_includes not_expired_events, permanent_event
  end

  test "should set expiration time" do
    event = Event.create!(type: "test_event")

    event.expires_in(1.week)

    assert event.expires_at.present?
    assert event.expires_at > Time.current
    assert event.expires_at < 2.weeks.from_now
  end

  test "should purge expired events" do
    expired_event = Event.create!(type: "expired_event", expires_at: 1.hour.ago)
    active_event = Event.create!(type: "active_event", expires_at: 1.hour.from_now)
    permanent_event = Event.create!(type: "permanent_event")

    Event.purge_expired

    assert_not Event.exists?(expired_event.id)
    assert Event.exists?(active_event.id)
    assert Event.exists?(permanent_event.id)
  end

  test "should work with polymorphic subjects" do
    feed_event = Event.create!(type: "feed_event", subject: feed)
    user_event = Event.create!(type: "user_event", subject: user)

    assert_equal "Feed", feed_event.subject_type
    assert_equal feed.id, feed_event.subject_id
    assert_equal feed, feed_event.subject

    assert_equal "User", user_event.subject_type
    assert_equal user.id, user_event.subject_id
    assert_equal user, user_event.subject
  end

  test "should store complex metadata in JSONB" do
    complex_metadata = {
      request: { url: "https://example.com", method: "GET" },
      response: { status: 200, headers: { "content-type" => "application/xml" } },
      timing: { duration_ms: 1500, timeout: false },
      tags: ["production", "feed-refresh"]
    }

    event = Event.create!(
      type: "complex_event",
      metadata: complex_metadata
    )

    # JSONB stores everything as strings, so deep stringify the keys
    expected_metadata = {
      "request" => { "url" => "https://example.com", "method" => "GET" },
      "response" => { "status" => 200, "headers" => { "content-type" => "application/xml" } },
      "timing" => { "duration_ms" => 1500, "timeout" => false },
      "tags" => ["production", "feed-refresh"]
    }

    assert_equal expected_metadata, event.metadata
    assert_equal "GET", event.metadata["request"]["method"]
    assert_equal 1500, event.metadata["timing"]["duration_ms"]
  end

  test "#user_relevant should exclude debug level events" do
    debug_event = Event.create!(type: "debug_event", level: :debug)
    info_event = Event.create!(type: "info_event", level: :info)
    warning_event = Event.create!(type: "warning_event", level: :warning)
    error_event = Event.create!(type: "error_event", level: :error)

    relevant_events = Event.user_relevant

    assert_not_includes relevant_events, debug_event
    assert_includes relevant_events, info_event
    assert_includes relevant_events, warning_event
    assert_includes relevant_events, error_event
  end

  test "#user_relevant should exclude expired events" do
    expired_event = Event.create!(type: "expired_event", level: :info, expires_at: 1.hour.ago)
    active_event = Event.create!(type: "active_event", level: :info, expires_at: 1.hour.from_now)
    permanent_event = Event.create!(type: "permanent_event", level: :info)

    relevant_events = Event.user_relevant

    assert_not_includes relevant_events, expired_event
    assert_includes relevant_events, active_event
    assert_includes relevant_events, permanent_event
  end

  test "#user_relevant should combine both filters" do
    excluded_debug = Event.create!(type: "debug_event", level: :debug)
    excluded_expired = Event.create!(type: "expired_info", level: :info, expires_at: 1.hour.ago)
    excluded_both = Event.create!(type: "expired_debug", level: :debug, expires_at: 1.hour.ago)
    included_event = Event.create!(type: "good_event", level: :info)

    relevant_events = Event.user_relevant

    assert_not_includes relevant_events, excluded_debug
    assert_not_includes relevant_events, excluded_expired
    assert_not_includes relevant_events, excluded_both
    assert_includes relevant_events, included_event
  end
end
