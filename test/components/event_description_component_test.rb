require "test_helper"
require "view_component/test_case"

class EventDescriptionComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user, name: "Test Feed")
  end

  def other_feed
    @other_feed ||= create(:feed, user: user, name: "Other Feed")
  end

  test "renders link for single feed event" do
    event = Event.create!(
      type: "feed_refresh",
      level: :info,
      subject: feed,
      user: user,
      message: "",
      metadata: {}
    )

    result = render_inline(EventDescriptionComponent.new(event: event))

    assert_includes result.to_html, "Test Feed"
    assert_includes result.to_html, "/feeds/#{feed.id}"
    assert_includes result.to_html, "refreshed successfully"
  end

  test "renders links for multiple feeds from metadata" do
    event = Event.create!(
      type: "access_token_validation_failed",
      level: :warning,
      subject: create(:access_token, user: user),
      user: user,
      message: "",
      metadata: { disabled_feed_ids: [feed.id, other_feed.id], disabled_count: 2 }
    )

    result = render_inline(EventDescriptionComponent.new(event: event))

    # When all feeds exist, show just the feed links
    assert_includes result.to_html, "Test Feed"
    assert_includes result.to_html, "Other Feed"
    assert_includes result.to_html, "/feeds/#{feed.id}"
    assert_includes result.to_html, "/feeds/#{other_feed.id}"
    assert_includes result.to_html, "Feeds disabled:"
    refute_includes result.to_html, "2 feeds"
  end

  test "includes error message for refresh errors" do
    event = Event.create!(
      type: "feed_refresh_error",
      level: :error,
      subject: feed,
      user: user,
      message: "Connection timeout",
      metadata: {}
    )

    result = render_inline(EventDescriptionComponent.new(event: event))

    assert_includes result.to_html, "Test Feed"
    assert_includes result.to_html, "refresh failed"
    assert_includes result.to_html, "Connection timeout"
  end

  test "handles events without feeds gracefully" do
    event = Event.create!(
      type: "email_changed",
      level: :info,
      subject: user,
      user: user,
      message: "",
      metadata: { old_email: "old@example.com", new_email: "new@example.com" }
    )

    result = render_inline(EventDescriptionComponent.new(event: event))

    assert_includes result.to_html, "Email address changed"
  end

  test "falls back to stored message when present" do
    event = Event.create!(
      type: "custom_event",
      level: :info,
      subject: user,
      user: user,
      message: "Custom message",
      metadata: {}
    )

    result = render_inline(EventDescriptionComponent.new(event: event))

    assert_includes result.to_html, "Custom message"
  end

  test "escapes HTML in fallback messages" do
    event = Event.create!(
      type: "test_event",
      level: :info,
      subject: user,
      user: user,
      message: "<script>alert('xss')</script>",
      metadata: {}
    )

    result = render_inline(EventDescriptionComponent.new(event: event))

    refute_includes result.to_html, "<script>"
    assert_includes result.to_html, "&lt;script&gt;"
  end

  test "preserves count when feeds are deleted" do
    feed1 = create(:feed, user: user, name: "Feed One")
    feed2 = create(:feed, user: user, name: "Feed Two")

    event = Event.create!(
      type: "access_token_validation_failed",
      level: :warning,
      subject: create(:access_token, user: user),
      user: user,
      message: "",
      metadata: { disabled_feed_ids: [feed1.id, feed2.id], disabled_count: 2 }
    )

    # Delete one of the feeds
    feed2.destroy!

    result = render_inline(EventDescriptionComponent.new(event: event))

    # Should show count and remaining feed
    assert_includes result.to_html, "Feeds disabled: 2 feeds:"
    assert_includes result.to_html, "Feed One"
    refute_includes result.to_html, "Feed Two"
  end

  test "shows count when all feeds are deleted" do
    feed1 = create(:feed, user: user, name: "Feed One")
    feed2 = create(:feed, user: user, name: "Feed Two")

    event = Event.create!(
      type: "access_token_validation_failed",
      level: :warning,
      subject: create(:access_token, user: user),
      user: user,
      message: "",
      metadata: { disabled_feed_ids: [feed1.id, feed2.id], disabled_count: 2 }
    )

    # Delete all feeds
    feed1.destroy!
    feed2.destroy!

    result = render_inline(EventDescriptionComponent.new(event: event))

    # Should show just the count when no feeds exist
    assert_includes result.to_html, "Feeds disabled: 2 feeds"
    refute_includes result.to_html, "Feed One"
    refute_includes result.to_html, "Feed Two"
  end

  test "escapes HTML in error messages" do
    feed = create(:feed, user: user, name: "Test Feed")
    event = Event.create!(
      type: "feed_refresh_error",
      level: :error,
      subject: feed,
      user: user,
      message: "<script>alert('xss')</script>",
      metadata: {}
    )

    result = render_inline(EventDescriptionComponent.new(event: event))

    refute_includes result.to_html, "<script>"
    assert_includes result.to_html, "&lt;script&gt;"
  end
end
