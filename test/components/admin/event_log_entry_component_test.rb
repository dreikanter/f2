require "test_helper"

class Admin::EventLogEntryComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  test "#call should link the user to the admin filter" do
    event = create(:event, user: user)

    result = render_inline(Admin::EventLogEntryComponent.new(event: event, href: "/admin/events/#{event.id}"))

    link = result.css("a[data-key='events.user']").first
    assert_not_nil link
    assert_equal "User ##{user.id}", link.text
    assert_includes link["href"], "filter%5Buser_id%5D=#{user.id}"
    assert_includes link["class"], "underline"
    assert_not_includes link["class"], "decoration-dotted"
  end

  test "#call should link the subject to the admin filter" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", subject: feed, user: user)

    result = render_inline(Admin::EventLogEntryComponent.new(event: event, href: "/admin/events/#{event.id}"))

    link = result.css("a[data-key='events.subject']").first
    assert_not_nil link
    assert_equal "Feed ##{feed.id}", link.text
    assert_includes link["href"], "/admin/events"
    assert_includes link["href"], "filter%5Bsubject_type%5D=Feed"
    assert_includes link["href"], "filter%5Bsubject_id%5D=#{feed.id}"
  end

  test "#call should show System for events without a user" do
    event = create(:event, user: nil)

    result = render_inline(Admin::EventLogEntryComponent.new(event: event, href: "/admin/events/#{event.id}"))

    label = result.css("[data-key='events.user']").first
    assert_not_nil label
    assert_equal "System", label.text
  end
end
