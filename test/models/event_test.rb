require "test_helper"

class EventTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed)
  end

  test "should create event with minimal attributes" do
    event = Event.create!(type: "TestEvent")

    assert_equal "TestEvent", event.type
    assert_equal "info", event.level
    assert_equal "", event.message
    assert_equal({}, event.metadata)
    assert_nil event.user
    assert_nil event.subject
    assert_nil event.expires_at
  end

  test "should create event with all attributes" do
    event = Event.create!(
      type: "FeedRefreshEvent",
      level: :error,
      message: "Feed refresh failed",
      metadata: { error: "timeout", retry_count: 3 },
      user: user,
      subject: feed,
      expires_at: 1.week.from_now
    )

    assert_equal "FeedRefreshEvent", event.type
    assert_equal "error", event.level
    assert_equal "Feed refresh failed", event.message
    assert_equal({ "error" => "timeout", "retry_count" => 3 }, event.metadata)
    assert_equal user, event.user
    assert_equal feed, event.subject
    assert event.expires_at.present?
  end

  test "should allow blank message" do
    event = Event.create!(type: "TestEvent", message: "")

    assert_equal "", event.message
  end

  test "should validate required fields" do
    event = Event.new

    assert_not event.valid?
    assert_includes event.errors[:type], "can't be blank"
  end

  test "should validate level enum" do
    event = Event.new(type: "TestEvent")

    assert event.valid?

    assert_raises(ArgumentError) do
      event.level = "invalid"
    end
  end

  test "should scope recent events" do
    old_event = Event.create!(type: "OldEvent", created_at: 2.days.ago)
    new_event = Event.create!(type: "NewEvent", created_at: 1.hour.ago)

    recent_events = Event.recent.limit(2)

    assert_equal [new_event, old_event], recent_events.to_a
  end

  test "should scope events for subject" do
    feed_event = Event.create!(type: "FeedEvent", subject: feed)
    user_event = Event.create!(type: "UserEvent", subject: user)

    feed_events = Event.for_subject(feed)

    assert_includes feed_events, feed_event
    assert_not_includes feed_events, user_event
  end

  test "should identify expired events" do
    expired_event = Event.create!(type: "ExpiredEvent", expires_at: 1.hour.ago)
    active_event = Event.create!(type: "ActiveEvent", expires_at: 1.hour.from_now)
    permanent_event = Event.create!(type: "PermanentEvent")

    assert expired_event.expired?
    assert_not active_event.expired?
    assert_not permanent_event.expired?
  end

  test "should scope expired events" do
    expired_event = Event.create!(type: "ExpiredEvent", expires_at: 1.hour.ago)
    active_event = Event.create!(type: "ActiveEvent", expires_at: 1.hour.from_now)
    permanent_event = Event.create!(type: "PermanentEvent")

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
    event = Event.create!(type: "TestEvent")

    event.expires_in(1.week)

    assert event.expires_at.present?
    assert event.expires_at > Time.current
    assert event.expires_at < 2.weeks.from_now
  end

  test "should purge expired events" do
    expired_event = Event.create!(type: "ExpiredEvent", expires_at: 1.hour.ago)
    active_event = Event.create!(type: "ActiveEvent", expires_at: 1.hour.from_now)
    permanent_event = Event.create!(type: "PermanentEvent")

    Event.purge_expired

    assert_not Event.exists?(expired_event.id)
    assert Event.exists?(active_event.id)
    assert Event.exists?(permanent_event.id)
  end

  test "should work with polymorphic subjects" do
    feed_event = Event.create!(type: "FeedEvent", subject: feed)
    user_event = Event.create!(type: "UserEvent", subject: user)

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
      type: "ComplexEvent",
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
end
