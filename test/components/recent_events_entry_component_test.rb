require "test_helper"

class RecentEventsEntryComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  test "#call should render description and a leading timestamp link" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_inline(RecentEventsEntryComponent.new(event: event, href: "/events/#{event.id}"))

    assert_not_nil result.css("[data-key='recent_events.description']").first
    assert_not_nil result.css("a[data-key='recent_events.timestamp'][href='/events/#{event.id}']").first
  end

  test "#call should not render a level badge" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_inline(RecentEventsEntryComponent.new(event: event, href: "/events/#{event.id}"))

    assert_not_includes result.text, "Info"
  end

  test "#call should render the event row with its data key" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_inline(RecentEventsEntryComponent.new(event: event, href: "/events/#{event.id}"))

    assert_not_nil result.css("li[data-key='recent_events.#{event.id}']").first
  end

  test "#call should show the imported posts count for feed_refresh events" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", level: :info, user: user, subject: feed)
    create(:event_reference, event: event, reference: create(:post, feed: feed))
    create(:event_reference, event: event, reference: create(:post, feed: feed))

    result = render_inline(RecentEventsEntryComponent.new(event: event, href: "/events/#{event.id}"))

    assert_equal "(+2)", result.css("[data-key='events.posts_count']").first&.text
  end

  test "#call should count only post references" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", level: :info, user: user, subject: feed)
    create(:event_reference, event: event, reference: create(:post, feed: feed))
    create(:event_reference, event: event, reference: user)

    result = render_inline(RecentEventsEntryComponent.new(event: event, href: "/events/#{event.id}"))

    assert_equal "(+1)", result.css("[data-key='events.posts_count']").first&.text
  end

  test "#call should not show a posts count when there are no references" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_inline(RecentEventsEntryComponent.new(event: event, href: "/events/#{event.id}"))

    assert_nil result.css("[data-key='events.posts_count']").first
  end

  test "#call should flag warning and error events with a severity dot" do
    error_event = create(:event, type: "error_event", level: :error, user: user)

    result = render_inline(RecentEventsEntryComponent.new(event: error_event, href: "/events/#{error_event.id}"))

    dot = result.css("[data-key='events.severity']").first
    assert_not_nil dot
    assert_includes dot["class"], "bg-red-500"
  end

  test "#call should not flag routine info events with a severity dot" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_inline(RecentEventsEntryComponent.new(event: event, href: "/events/#{event.id}"))

    assert_nil result.css("[data-key='events.severity']").first
  end
end
