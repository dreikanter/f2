require "test_helper"

class EventDescriptionRendererTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user, name: "Test Feed")
  end

  def other_feed
    @other_feed ||= create(:feed, user: user, name: "Other Feed")
  end

  test "#render should generate link for single feed event" do
    event = Event.create!(
      type: "feed_refresh",
      level: :info,
      subject: feed,
      user: user,
      message: "",
      metadata: {}
    )

    renderer = EventDescriptionRenderer.new(event)
    result = renderer.render

    assert_includes result, "Test Feed"
    assert_includes result, "/feeds/#{feed.id}"
    assert_includes result, "refreshed successfully"
  end

  test "#render should generate links for multiple feeds from metadata" do
    event = Event.create!(
      type: "access_token_validation_failed",
      level: :warning,
      subject: create(:access_token, user: user),
      user: user,
      message: "",
      metadata: { disabled_feed_ids: [feed.id, other_feed.id], disabled_count: 2 }
    )

    renderer = EventDescriptionRenderer.new(event)
    result = renderer.render

    assert_includes result, "Test Feed"
    assert_includes result, "Other Feed"
    assert_includes result, "/feeds/#{feed.id}"
    assert_includes result, "/feeds/#{other_feed.id}"
    assert_includes result, "2 feeds disabled"
  end

  test "#render should include error message for refresh errors" do
    event = Event.create!(
      type: "feed_refresh_error",
      level: :error,
      subject: feed,
      user: user,
      message: "",
      metadata: { error_message: "Connection timeout" }
    )

    renderer = EventDescriptionRenderer.new(event)
    result = renderer.render

    assert_includes result, "Test Feed"
    assert_includes result, "refresh failed"
    assert_includes result, "Connection timeout"
  end

  test "#render should handle events without feeds gracefully" do
    event = Event.create!(
      type: "email_changed",
      level: :info,
      subject: user,
      user: user,
      message: "",
      metadata: { old_email: "old@example.com", new_email: "new@example.com" }
    )

    renderer = EventDescriptionRenderer.new(event)
    result = renderer.render

    assert_includes result, "Email address changed"
    assert result.html_safe?
  end

  test "#render should fall back to stored message when present" do
    event = Event.create!(
      type: "custom_event",
      level: :info,
      subject: user,
      user: user,
      message: "Custom message",
      metadata: {}
    )

    renderer = EventDescriptionRenderer.new(event)
    result = renderer.render

    assert_includes result, "Custom message"
  end

  test "#render should escape HTML in fallback messages" do
    event = Event.create!(
      type: "test_event",
      level: :info,
      subject: user,
      user: user,
      message: "<script>alert('xss')</script>",
      metadata: {}
    )

    renderer = EventDescriptionRenderer.new(event)
    result = renderer.render

    refute_includes result, "<script>"
    assert_includes result, "&lt;script&gt;"
  end

  test "#render should return html_safe string" do
    event = Event.create!(
      type: "feed_refresh",
      level: :info,
      subject: feed,
      user: user,
      message: "",
      metadata: {}
    )

    renderer = EventDescriptionRenderer.new(event)
    result = renderer.render

    assert result.html_safe?
    assert_kind_of ActiveSupport::SafeBuffer, result
  end

  test "#render should preserve count when feeds are deleted" do
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

    renderer = EventDescriptionRenderer.new(event)
    result = renderer.render

    # Should still show original count of 2, not 1
    assert_includes result, "2 feeds disabled"
    assert_includes result, "Feed One"
    refute_includes result, "Feed Two"
  end

  test "#render should escape HTML in error messages" do
    feed = create(:feed, user: user, name: "Test Feed")
    event = Event.create!(
      type: "feed_refresh_error",
      level: :error,
      subject: feed,
      user: user,
      message: "",
      metadata: { error_message: "<script>alert('xss')</script>" }
    )

    renderer = EventDescriptionRenderer.new(event)
    result = renderer.render

    refute_includes result, "<script>"
    assert_includes result, "&lt;script&gt;"
  end
end
