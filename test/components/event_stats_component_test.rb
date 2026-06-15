require "test_helper"
require "view_component/test_case"

class EventStatsComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user, name: "Test Feed")
  end

  test "#call should render the core event stats" do
    event = create(:event, type: "TestEvent", level: :warning, subject: feed)

    result = render_inline(EventStatsComponent.new(event: event))

    assert_includes result.to_html, "TestEvent"
    assert_includes result.to_html, "Warning"
    assert_includes result.to_html, "Feed ##{feed.id}"
  end

  test "#call should not render feed refresh stats for other event types" do
    event = create(:event, type: "TestEvent", metadata: { stats: { new_posts: 3, total_duration: 5.0 } })

    result = render_inline(EventStatsComponent.new(event: event))

    assert_empty result.css('[data-key="events.new_posts.label"]')
    assert_empty result.css('[data-key="events.duration.label"]')
  end

  test "#call should render imported posts and duration for feed refresh events" do
    event = create(:event, type: "feed_refresh", metadata: { stats: { new_posts: 4, total_duration: 12.34 } })

    result = render_inline(EventStatsComponent.new(event: event))

    assert_equal "New posts", result.css('[data-key="events.new_posts.label"]').text
    assert_equal "4", result.css('[data-key="events.new_posts.value"]').text
    assert_equal "Duration", result.css('[data-key="events.duration.label"]').text
    assert_equal "12.3s", result.css('[data-key="events.duration.value"]').text
  end

  test "#call should format long refresh durations in minutes and seconds" do
    event = create(:event, type: "feed_refresh", metadata: { stats: { total_duration: 95.0 } })

    result = render_inline(EventStatsComponent.new(event: event))

    assert_equal "1m 35s", result.css('[data-key="events.duration.value"]').text
  end

  test "#call should skip feed refresh stats when metadata is missing them" do
    event = create(:event, type: "feed_refresh", metadata: {})

    result = render_inline(EventStatsComponent.new(event: event))

    assert_empty result.css('[data-key="events.new_posts.label"]')
    assert_empty result.css('[data-key="events.duration.label"]')
  end
end
