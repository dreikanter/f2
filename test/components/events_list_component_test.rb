require "test_helper"

class EventsListComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  test "#call should render each event as a card inside the list" do
    event1 = create(:event, type: "feed_refresh", level: :info, user: user)
    event2 = create(:event, type: "post_withdrawn", level: :warning, user: user)

    result = render_inline(EventsListComponent.new(events: [event1, event2]))

    assert_not_nil result.css("[data-key='events.list'] > [data-event-id='#{event1.id}']").first
    assert_not_nil result.css("[data-key='events.list'] > [data-event-id='#{event2.id}']").first
  end

  test "#call should wire up the polling controller when endpoint is given" do
    event = create(:event, user: user)

    result = render_inline(EventsListComponent.new(events: [event], endpoint: "/events?display=brief"))

    host = result.css("##{EventsListComponent::DOM_ID}").first
    assert_not_nil host
    assert_equal "polling", host["data-controller"]
    assert_equal "/events?display=brief", host["data-polling-endpoint-value"]
    assert_equal event.id.to_s, host["data-last-event-id"]
    assert_equal "false", host["data-polling-indicate-busy-value"]
  end

  test "#call should omit polling chrome when no endpoint is given" do
    event = create(:event, user: user)

    result = render_inline(EventsListComponent.new(events: [event]))

    assert_empty result.css("[data-controller='polling']")
  end

  test "#call should render pagination links when urls are given" do
    event = create(:event, user: user)

    result = render_inline(EventsListComponent.new(events: [event], older_url: "/events?before=5", newer_url: "/events?after=9"))

    assert_equal "/events?before=5", result.css("a[data-key='events.older']").first["href"]
    assert_equal "/events?after=9", result.css("a[data-key='events.newer']").first["href"]
  end

  test "#call should omit pagination nav when no urls are given" do
    event = create(:event, user: user)

    result = render_inline(EventsListComponent.new(events: [event]))

    assert_empty result.css("[data-key='events.pagination']")
  end

  test "#call should render the empty state when events array is empty" do
    result = render_inline(EventsListComponent.new(events: []))

    assert_not_nil result.css("[data-key='empty-state']").first
    assert_empty result.css("li")
  end
end
