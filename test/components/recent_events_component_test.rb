require "test_helper"
require "view_component/test_case"

class RecentEventsComponentTest < ViewComponent::TestCase
  include ActiveSupport::Testing::TimeHelpers

  def user
    @user ||= create(:user)
  end

  test "#render should display events with feed links" do
    travel_to Time.current do
      feed = create(:feed, user: user, name: "Test Feed")
      event = Event.create!(
        type: "feed_refresh",
        level: :info,
        subject: feed,
        message: "",
        user: user,
        created_at: 1.hour.ago
      )

      result = render_inline(RecentEventsComponent.new(events: [event]))

      item = result.css('[data-key="recent_events.%d"]' % event.id).first
      assert_not_nil item
      assert_match(/Test Feed/, result.text)
      assert_match(/refreshed successfully/, result.text)
      assert_match(/ago/, result.text)
    end
  end

  test "#render should display fallback messages for events without feeds" do
    event = Event.create!(
      type: "email_changed",
      level: :info,
      message: "",
      user: user
    )

    result = render_inline(RecentEventsComponent.new(events: [event]))

    assert_match(/Email address changed/, result.text)
  end

  test "#render should display multiple events" do
    feed = create(:feed, user: user)
    post = create(:post, feed: feed)
    event1 = Event.create!(type: "feed_refresh", level: :info, message: "First event", subject: post, user: user)
    event2 = Event.create!(type: "post_withdrawn", level: :info, message: "Second event", subject: post, user: user)

    result = render_inline(RecentEventsComponent.new(events: [event1, event2]))

    assert_match(/First event/, result.text)
    assert_match(/Second event/, result.text)
  end

  test "#render should return nil when no events" do
    result = render_inline(RecentEventsComponent.new(events: []))

    assert_equal "", result.to_html.strip
  end

  test "#render should use i18n messages for known event types" do
    feed = create(:feed, user: user, name: "Example Feed")
    post = create(:post, feed: feed)
    event1 = Event.create!(type: "feed_refresh", level: :info, message: "", subject: feed, user: user)
    event2 = Event.create!(type: "feed_refresh_error", level: :error, message: "", subject: feed, user: user)
    event3 = Event.create!(type: "post_withdrawn", level: :info, message: "", subject: post, user: user)

    result = render_inline(RecentEventsComponent.new(events: [event1, event2, event3]))

    assert_match(/refreshed successfully/, result.text)
    assert_match(/refresh failed/, result.text)
    assert_match(/Post withdrawn/, result.text)
  end

  test "#render should humanize unknown event types" do
    event = Event.create!(type: "unknown_event_type", level: :info, message: "", user: user)

    result = render_inline(RecentEventsComponent.new(events: [event]))

    assert_match(/Unknown event type/, result.text)
  end
end
