require "test_helper"

class EventLogEntryComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  test "#call should render the event type, level badge and link" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_inline(EventLogEntryComponent.new(event: event, href: "/events/#{event.id}"))

    assert_not_nil result.css("[data-key='events.#{event.id}']").first
    assert_equal "feed_refresh", result.css("[data-key='events.type']").first.text
    assert_not_nil result.css("a[href='/events/#{event.id}']").first
  end

  test "#call should render subject context when present" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", subject: feed, user: user)

    result = render_inline(EventLogEntryComponent.new(event: event, href: "/events/#{event.id}"))

    assert_equal "Feed ##{feed.id}", result.css("[data-key='events.subject']").first.text
  end

  test "#call should link the user to the admin filter when admin" do
    event = create(:event, user: user)

    result = render_inline(EventLogEntryComponent.new(event: event, href: "/admin/events/#{event.id}", admin: true))

    link = result.css("a[data-key='events.user']").first
    assert_not_nil link
    assert_equal "User ##{user.id}", link.text
  end

  test "#call should not link the user when not admin" do
    event = create(:event, user: user)

    result = render_inline(EventLogEntryComponent.new(event: event, href: "/events/#{event.id}"))

    assert_not_nil result.css("span[data-key='events.user']").first
    assert_empty result.css("a[data-key='events.user']")
  end
end
