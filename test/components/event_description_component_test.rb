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

  test "#call should render link for single feed event" do
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

  test "#call should render links for multiple feeds from metadata" do
    event = Event.create!(
      type: "access_token_validation_failed",
      level: :warning,
      subject: create(:access_token, user: user),
      user: user,
      message: "",
      metadata: { disabled_feed_ids: [feed.id, other_feed.id] }
    )

    result = render_inline(EventDescriptionComponent.new(event: event))

    # When all feeds exist, show just the feed links
    assert_includes result.to_html, "Test Feed"
    assert_includes result.to_html, "Other Feed"
    assert_includes result.to_html, "/feeds/#{feed.id}"
    assert_includes result.to_html, "/feeds/#{other_feed.id}"
    assert_includes result.to_html, "Feeds disabled:"
    assert_not_includes result.to_html, "2 feeds"
  end

  test "#call should include error message and stage for refresh errors" do
    event = Event.create!(
      type: "feed_refresh_error",
      level: :error,
      subject: feed,
      user: user,
      message: "Connection timeout",
      metadata: { error: { stage: "load_feed_contents" } }
    )

    result = render_inline(EventDescriptionComponent.new(event: event))

    assert_includes result.to_html, "Test Feed"
    assert_includes result.to_html, "refresh failed at load feed contents"
    assert_includes result.to_html, "Connection timeout"
  end

  test "#call should handle events without feeds gracefully" do
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

  test "#call should fall back to stored message when present" do
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

  test "#call should escape HTML in fallback messages" do
    event = Event.create!(
      type: "test_event",
      level: :info,
      subject: user,
      user: user,
      message: "<script>alert('xss')</script>",
      metadata: {}
    )

    result = render_inline(EventDescriptionComponent.new(event: event))

    assert_not_includes result.to_html, "<script>"
    assert_includes result.to_html, "&lt;script&gt;"
  end

  test "#call should show count when all feeds are deleted" do
    feed1 = create(:feed, user: user, name: "Feed One")
    feed2 = create(:feed, user: user, name: "Feed Two")

    event = Event.create!(
      type: "access_token_validation_failed",
      level: :warning,
      subject: create(:access_token, user: user),
      user: user,
      message: "",
      metadata: { disabled_feed_ids: [feed1.id, feed2.id] }
    )

    feed1.destroy!
    feed2.destroy!

    result = render_inline(EventDescriptionComponent.new(event: event))

    assert_equal "Token validation failed. Feeds disabled: 2 deleted feeds", result.to_html
  end

  test "#call should render links and deleted feed counts without escaping HTML" do
    feed1 = create(:feed, user: user, name: "Feed One")
    feed2 = create(:feed, user: user, name: "Feed Two")

    event = Event.create!(
      type: "access_token_validation_failed",
      level: :warning,
      subject: create(:access_token, user: user),
      user: user,
      message: "",
      metadata: { disabled_feed_ids: [feed1.id, feed2.id] }
    )

    feed2.destroy!

    result = render_inline(EventDescriptionComponent.new(event: event))

    assert_includes result.to_html, %(<a class="ff-link" href="/feeds/#{feed1.id}">Feed One</a>)
    assert_includes result.to_html, "1 deleted feed"
  end

  test "#call should escape HTML in error messages" do
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

    assert_not_includes result.to_html, "<script>"
    assert_includes result.to_html, "&lt;script&gt;"
  end

  test "#call should handle dotted event types from Resend webhooks" do
    event = Event.create!(
      type: "resend.email.email_bounced",
      level: :warning,
      subject: user,
      user: user,
      message: "",
      metadata: {}
    )

    result = render_inline(EventDescriptionComponent.new(event: event))

    # Should find i18n key events.resend_email_bounced.description
    # by normalizing resend.email.email_bounced -> resend_email_bounced
    assert_includes result.to_html, "Email bounced"
  end
end
