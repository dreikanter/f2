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
    assert_includes result.to_html, "refreshed"
  end

  test ".for should preserve the type-specific subclass in admin mode" do
    event = Event.create!(type: "feed_refresh", level: :info, subject: feed, user: user, message: "", metadata: {})

    assert_kind_of FeedRefreshDescriptionComponent, Admin::EventDescriptionComponent.for(event)
  end

  test "#call should link the feed to the admin path in admin mode" do
    event = Event.create!(
      type: "feed_refresh",
      level: :info,
      subject: feed,
      user: user,
      message: "",
      metadata: {}
    )

    result = render_inline(Admin::EventDescriptionComponent.for(event))

    assert_includes result.to_html, "/admin/feeds/#{feed.id}"
    assert_not_includes result.css("a").map { |a| a["href"] }, "/feeds/#{feed.id}"
  end

  test ".for should pick the feed refresh subclass for refresh events" do
    event = Event.create!(type: "feed_refresh", level: :info, subject: feed, user: user, message: "", metadata: {})

    assert_instance_of FeedRefreshDescriptionComponent, EventDescriptionComponent.for(event)
  end

  test ".for should pick the auto-disable subclass for feed_auto_disabled events" do
    event = Event.create!(type: "feed_auto_disabled", level: :warning, subject: feed, user: user, message: "", metadata: {})

    assert_instance_of FeedAutoDisabledDescriptionComponent, EventDescriptionComponent.for(event)
  end

  test ".for should fall back to the base component for other event types" do
    event = Event.create!(type: "email_changed", level: :info, subject: user, user: user, message: "", metadata: {})

    assert_instance_of EventDescriptionComponent, EventDescriptionComponent.for(event)
  end

  test ".for should pick the target-group-unavailable subclass" do
    event = Event.create!(type: "feed_target_group_unavailable", level: :warning, subject: feed, user: user, metadata: {})

    assert_instance_of FeedTargetGroupUnavailableDescriptionComponent, EventDescriptionComponent.for(event)
  end

  test "#call should render specific copy for a known target-group-unavailable reason" do
    event = Event.create!(
      type: "feed_target_group_unavailable",
      level: :warning,
      subject: feed,
      user: user,
      metadata: { reason: "posting_denied", target_group: "cats", details: "You can not post to some of destinations: cats" }
    )

    result = render_inline(EventDescriptionComponent.for(event)).to_html

    assert_includes result, "Test Feed"
    assert_includes result, "lost permission to post to its FreeFeed group"
  end

  test "#call should render default copy when the reason is missing or unknown" do
    event = Event.create!(
      type: "feed_target_group_unavailable",
      level: :warning,
      subject: feed,
      user: user,
      metadata: { reason: "something_new" }
    )

    result = render_inline(EventDescriptionComponent.for(event)).to_html

    assert_includes result, "its FreeFeed group is no longer available"
  end

  test "#call should never expose the raw API response for target-group-unavailable events" do
    event = Event.create!(
      type: "feed_target_group_unavailable",
      level: :warning,
      subject: feed,
      user: user,
      metadata: { reason: "group_not_found", details: "Account 'cats' was not found" }
    )

    result = render_inline(EventDescriptionComponent.for(event)).to_html

    assert_not_includes result, "Account 'cats' was not found"
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
    assert_includes result.to_html, "stopped working"
    assert_not_includes result.to_html, "2 feeds"
  end

  test "#call should include the error message for refresh errors" do
    event = Event.create!(
      type: "feed_refresh",
      level: :error,
      subject: feed,
      user: user,
      message: "Connection timeout",
      metadata: { status: "failed", error: { stage: "load_feed_contents" } }
    )

    result = render_inline(EventDescriptionComponent.for(event))

    assert_includes result.to_html, "Test Feed"
    assert_includes result.to_html, "couldn't refresh"
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

    assert_includes result.to_html, "Email address updated"
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

    assert_equal "FreeFeed token stopped working; disabled 2 deleted feeds", result.to_html
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

    assert_includes result.to_html, %(<a class="font-medium text-brand underline underline-offset-4 transition hover:text-brand-hover" href="/feeds/#{feed1.id}">Feed One</a>)
    assert_includes result.to_html, "1 deleted feed"
  end

  test "#call should escape HTML in error messages" do
    feed = create(:feed, user: user, name: "Test Feed")
    event = Event.create!(
      type: "feed_refresh",
      level: :error,
      subject: feed,
      user: user,
      message: "<script>alert('xss')</script>",
      metadata: { status: "failed" }
    )

    result = render_inline(EventDescriptionComponent.for(event))

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
