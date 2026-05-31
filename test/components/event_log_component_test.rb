require "test_helper"

class EventLogComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  test "#call should yield each event to the block" do
    event1 = create(:event, type: "first_event", user: user)
    event2 = create(:event, type: "second_event", user: user)

    result = render_inline(EventLogComponent.new(events: [event1, event2], endpoint: "/events", dom_id: "log")) do |event|
      "entry-#{event.type}"
    end

    assert_includes result.text, "entry-first_event"
    assert_includes result.text, "entry-second_event"
  end

  test "#call should expose the polling host and threshold" do
    event = create(:event, user: user)

    result = render_inline(EventLogComponent.new(events: [event], endpoint: "/events", dom_id: "log")) { |e| e.type }

    host = result.css("#log").first
    assert_not_nil host
    assert_equal "polling", host["data-controller"]
    assert_equal "/events", host["data-polling-endpoint-value"]
    assert_equal event.id.to_s, host["data-last-event-id"]
  end

  test "#call should render a refresh control" do
    result = render_inline(EventLogComponent.new(events: [create(:event, user: user)], endpoint: "/events", dom_id: "log")) { |e| e.type }

    refresh = result.css("[data-key='events.refresh']").first
    assert_not_nil refresh
    assert_equal "polling#refresh", refresh["data-action"]
  end

  test "#call should render the empty state without invoking the block" do
    result = render_inline(EventLogComponent.new(events: [], endpoint: "/events", dom_id: "log")) do |_event|
      raise "block should not be called when there are no events"
    end

    assert_not_nil result.css("[data-key='empty-state']").first
    assert_empty result.css("[data-key='events.list']")
  end
end
