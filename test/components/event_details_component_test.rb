require "test_helper"
require "view_component/test_case"

class EventDetailsComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user, name: "Test Feed")
  end

  test ".for should return the base component for generic events" do
    event = create(:event, type: "generic_event")

    assert_instance_of EventDetailsComponent, EventDetailsComponent.for(event)
  end

  test ".for should pick the feed refresh subclass for refresh events" do
    event = create(:event, type: "feed_refresh")

    assert_instance_of FeedRefreshDetailsComponent, EventDetailsComponent.for(event)
  end

  test "#call should render the common rows without admin extras" do
    event = create(:event, type: "owned_event", level: :warning, subject: feed)

    result = render_inline(EventDetailsComponent.for(event))

    assert_equal "owned_event", result.css('[data-key="events.type"]').text
    assert_includes result.to_html, "Warning"
    assert_includes result.to_html, "Feed ##{feed.id}"
    assert_empty result.css('[data-key="admin.event.user"]')
    assert_empty result.css('[data-key="admin.events.type"]')
  end

  test "#call should render admin rows and links when admin" do
    event = create(:event, type: "owned_event", user: user, subject: feed)

    result = render_inline(EventDetailsComponent.for(event, admin: true))

    assert_equal "owned_event", result.css('[data-key="admin.events.type"]').text
    assert_equal "User ##{event.user_id}", result.css("a[data-key='admin.event.user']").text
    assert_equal "Feed", result.css("a[data-key='admin.event.subject.type']").text
  end

  test "#call should append imported posts and duration for feed refresh events" do
    event = create(:event, type: "feed_refresh", metadata: { stats: { new_posts: 4, total_duration: 12.34 } })

    result = render_inline(EventDetailsComponent.for(event))

    assert_equal "New posts", result.css('[data-key="events.new_posts.label"]').text
    assert_equal "4", result.css('[data-key="events.new_posts.value"]').text
    assert_equal "Duration", result.css('[data-key="events.duration.label"]').text
    assert_equal "12.3s", result.css('[data-key="events.duration.value"]').text
  end

  test "#call should format long refresh durations in minutes and seconds" do
    event = create(:event, type: "feed_refresh", metadata: { stats: { total_duration: 95.0 } })

    result = render_inline(EventDetailsComponent.for(event))

    assert_equal "1m 35s", result.css('[data-key="events.duration.value"]').text
  end

  test "#call should skip feed refresh extras when stats are missing" do
    event = create(:event, type: "feed_refresh", metadata: {})

    result = render_inline(EventDetailsComponent.for(event))

    assert_empty result.css('[data-key="events.new_posts.label"]')
    assert_empty result.css('[data-key="events.duration.label"]')
  end
end
