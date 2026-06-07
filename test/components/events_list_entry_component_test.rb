require "test_helper"

class EventsListEntryComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  test "#call should render description, timestamp link and identity hooks" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_inline(EventsListEntryComponent.new(event: event, href: "/events/#{event.id}"))

    entry = result.css("[data-key='events.entry']").first
    assert_not_nil entry
    assert_equal "feed_refresh", entry["data-event-type"]
    assert_equal event.id.to_s, entry["data-event-id"]
    assert_not_nil result.css("[data-key='events.description']").first
    assert_not_nil result.css("a[data-key='events.timestamp'][href='/events/#{event.id}']").first
  end

  test "#call should not render the level badge or raw type text" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_inline(EventsListEntryComponent.new(event: event, href: "/events/#{event.id}"))

    assert_not_includes result.text, "Info"
    assert_empty result.css("code")
  end

  test "#call should not nest the description's links inside the detail link" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", subject: feed, user: user)

    result = render_inline(EventsListEntryComponent.new(event: event, href: "/events/#{event.id}"))

    detail = result.css("a[href='/events/#{event.id}']")
    assert_equal 1, detail.size
    assert_equal "events.timestamp", detail.first["data-key"]
    assert_empty result.css("a[href='/events/#{event.id}'] a")
  end

  test "#call should render the subject filter chip when a subject is present" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", subject: feed, user: user)

    result = render_inline(EventsListEntryComponent.new(event: event, href: "/events/#{event.id}"))

    link = result.css("a[data-key='events.subject']").first
    assert_not_nil link
    assert_equal "Feed ##{feed.id}", link.text
    assert_includes link["href"], "filter%5Bsubject_type%5D=Feed"
    assert_includes link["href"], "filter%5Bsubject_id%5D=#{feed.id}"
    assert_not_includes link["href"], "/admin/"
  end

  test "#call should flag warning and error events with a severity dot" do
    event = create(:event, type: "error_event", level: :error, user: user)

    result = render_inline(EventsListEntryComponent.new(event: event, href: "/events/#{event.id}"))

    dot = result.css("[data-key='events.severity']").first
    assert_not_nil dot
    assert_includes dot["class"], "bg-red-500"
  end

  test "#call should not flag routine info events with a severity dot" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_inline(EventsListEntryComponent.new(event: event, href: "/events/#{event.id}"))

    assert_nil result.css("[data-key='events.severity']").first
  end
end
