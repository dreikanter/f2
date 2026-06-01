require "test_helper"

class RecentEventsListComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  test "#call should render each event as a compact list item" do
    event1 = create(:event, type: "feed_refresh", level: :info, user: user)
    event2 = create(:event, type: "post_withdrawn", level: :warning, user: user)
    events = [event1, event2]

    result = render_inline(RecentEventsListComponent.new(events: events))

    assert_not_nil result.css("li[data-key='recent_events.#{event1.id}']").first
    assert_not_nil result.css("li[data-key='recent_events.#{event2.id}']").first
  end

  test "#call should wire up the polling controller when endpoint is given" do
    event = create(:event, user: user)

    result = render_inline(RecentEventsListComponent.new(events: [event], endpoint: "/events?display=brief"))

    host = result.css("##{RecentEventsListComponent::DOM_ID}").first
    assert_not_nil host
    assert_equal "polling", host["data-controller"]
    assert_equal "/events?display=brief", host["data-polling-endpoint-value"]
    assert_equal event.id.to_s, host["data-last-event-id"]
    assert_equal "false", host["data-polling-indicate-busy-value"]
  end

  test "#call should omit polling chrome when no endpoint is given" do
    event = create(:event, user: user)

    result = render_inline(RecentEventsListComponent.new(events: [event]))

    assert_empty result.css("[data-controller='polling']")
  end

  test "#call should render the empty state when events array is empty" do
    result = render_inline(RecentEventsListComponent.new(events: []))

    assert_not_nil result.css("[data-key='empty-state']").first
    assert_empty result.css("li")
  end
end
