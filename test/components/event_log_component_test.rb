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

  test "#call should wrap entries in a ul list by default" do
    event = create(:event, user: user)

    result = render_inline(EventLogComponent.new(events: [event])) { |log| log.with_entry { "entry" } }

    assert_not_nil result.css("ul[data-key='events.list']").first
  end

  test "#call should use a card container when list is disabled" do
    event = create(:event, user: user)

    result = render_inline(EventLogComponent.new(events: [event], list: false)) { |log| log.with_entry { "entry" } }

    assert_not_nil result.css("div[data-key='events.list']").first
    assert_empty result.css("ul[data-key='events.list']")
  end

  test "#call should expose the polling host and threshold" do
    event = create(:event, user: user)

    result = render_inline(EventLogComponent.new(events: [event], endpoint: "/events")) { |log| log.with_entry { event.type } }

    host = result.css("[data-key='events.log']").first
    assert_not_nil host
    assert_equal "polling", host["data-controller"]
    assert_equal "/events", host["data-polling-endpoint-value"]
    assert_equal event.id.to_s, host["data-last-event-id"]
    # Opt out of the busy indicator so the live log stays interactive while it
    # polls (the JS controller would otherwise set aria-busy, which globally
    # disables pointer events).
    assert_equal "false", host["data-polling-indicate-busy-value"]
  end

  test "#call should omit polling chrome when no endpoint is given" do
    event = create(:event, user: user)

    result = render_inline(EventLogComponent.new(events: [event])) { |log| log.with_entry { event.type } }

    assert_empty result.css("[data-controller='polling']")
  end

  test "#call should render cursor pagination links when urls are given" do
    event = create(:event, user: user)

    result = render_inline(EventLogComponent.new(events: [event], older_url: "/admin/events?before=5", newer_url: "/admin/events?after=9")) do |log|
      log.with_entry { event.type }
    end

    assert_equal "/admin/events?before=5", result.css("a[data-key='events.older']").first["href"]
    assert_equal "/admin/events?after=9", result.css("a[data-key='events.newer']").first["href"]
  end

  test "#call should omit pagination nav when no urls are given" do
    event = create(:event, user: user)

    result = render_inline(EventLogComponent.new(events: [event])) { |log| log.with_entry { event.type } }

    assert_empty result.css("[data-key='events.pagination']")
  end

  test "#call should render the empty state when no entries are added" do
    result = render_inline(EventLogComponent.new(events: [], endpoint: "/events"))

    assert_not_nil result.css("[data-key='empty-state']").first
    assert_empty result.css("[data-key='events.list']")
  end
end
