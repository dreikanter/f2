require "test_helper"

class EventLogComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  test "#call should render each entry slot" do
    event1 = create(:event, type: "first_event", user: user)
    event2 = create(:event, type: "second_event", user: user)
    events = [event1, event2]

    result = render_inline(EventLogComponent.new(events: events, endpoint: "/events")) do |log|
      events.each { |event| log.with_entry { "entry-#{event.type}" } }
    end

    assert_includes result.text, "entry-first_event"
    assert_includes result.text, "entry-second_event"
    assert_not_nil result.css("[data-key='events.list']").first
  end

  test "#call should expose the polling host and threshold" do
    event = create(:event, user: user)

    result = render_inline(EventLogComponent.new(events: [event], endpoint: "/events")) { |log| log.with_entry { event.type } }

    host = result.css("[data-key='events.log']").first
    assert_not_nil host
    assert_equal "polling", host["data-controller"]
    assert_equal "/events", host["data-polling-endpoint-value"]
    assert_equal event.id.to_s, host["data-last-event-id"]
  end

  test "#call should render a refresh control" do
    event = create(:event, user: user)
    result = render_inline(EventLogComponent.new(events: [event], endpoint: "/events")) { |log| log.with_entry { event.type } }

    refresh = result.css("[data-key='events.refresh']").first
    assert_not_nil refresh
    assert_equal "polling#refresh", refresh["data-action"]
  end

  test "#call should render the empty state when no entries are added" do
    result = render_inline(EventLogComponent.new(events: [], endpoint: "/events"))

    assert_not_nil result.css("[data-key='empty-state']").first
    assert_empty result.css("[data-key='events.list']")
  end
end
