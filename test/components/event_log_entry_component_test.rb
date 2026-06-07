require "test_helper"

class EventLogEntryComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  test "#call should render a description, timestamp link and type hook" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_inline(EventLogEntryComponent.new(event: event, href: "/events/#{event.id}"))

    entry = result.css("[data-key='events.entry']").first
    assert_not_nil entry
    assert_equal "feed_refresh", entry["data-event-type"]
    assert_not_nil result.css("[data-key='events.description']").first
    assert_not_nil result.css("a[href='/events/#{event.id}']").first
  end

  test "#call should not render the level badge or raw type text" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_inline(EventLogEntryComponent.new(event: event, href: "/events/#{event.id}"))

    assert_not_includes result.text, "Info"
    assert_empty result.css("code")
  end

  test "#call should not wrap the entry in an anchor (no nested links)" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", subject: feed, user: user)

    result = render_inline(EventLogEntryComponent.new(event: event, href: "/events/#{event.id}"))

    # The detail link is the timestamp only, rendered once...
    detail = result.css("a[href='/events/#{event.id}']")
    assert_equal 1, detail.size
    assert_equal "events.timestamp", detail.first["data-key"]
    # ...and the feed link in the description is not nested inside it.
    assert_empty result.css("a[href='/events/#{event.id}'] a")
  end

  test "#call should render subject context when present" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", subject: feed, user: user)

    result = render_inline(EventLogEntryComponent.new(event: event, href: "/events/#{event.id}"))

    link = result.css("a[data-key='events.subject']").first
    assert_not_nil link
    assert_equal "Feed ##{feed.id}", link.text
    assert_includes link["href"], "filter%5Bsubject_type%5D=Feed"
    assert_includes link["href"], "filter%5Bsubject_id%5D=#{feed.id}"
    assert_not_includes link["href"], "/admin/"
  end

  test "#call should never show an owner (entries belong to the current user)" do
    event = create(:event, user: user)

    result = render_inline(EventLogEntryComponent.new(event: event, href: "/events/#{event.id}"))

    assert_empty result.css("[data-key='events.user']")
  end
end
