require "test_helper"

class Admin::EventLogEntryComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def render_entry(event)
    render_inline(Admin::EventLogEntryComponent.new(event: event, href: "/admin/events/#{event.id}"))
  end

  test "#call should render the humanized message in the card body" do
    event = create(:event, message: "Something happened", user: user)

    result = render_entry(event)

    description = result.css("[data-key='events.description']").first
    assert_not_nil description
    assert_includes description.text, "Something happened"
  end

  test "#call should render a severity icon instead of a level badge" do
    event = create(:event, level: :warning, user: user)

    result = render_entry(event)

    icon = result.css("[data-key='events.severity'] svg").first
    assert_not_nil icon
    assert_equal "Warning", icon["aria-label"]
    assert_includes icon["class"], "text-amber-500"
    assert_not_includes result.text, "Warning"
  end

  test "#call should link the footer timestamp to the event page" do
    event = create(:event, user: user)

    result = render_entry(event)

    link = result.css("a[data-key='events.timestamp']").first
    assert_not_nil link
    assert_equal "/admin/events/#{event.id}", link["href"]
  end

  test "#call should link the type to the admin filter" do
    event = create(:event, type: "custom_event", user: user)

    result = render_entry(event)

    link = result.css("a[data-key='events.type']").first
    assert_not_nil link
    assert_equal "custom_event", link.text
    assert_includes link["href"], "/admin/events"
    assert_includes link["href"], "filter%5Btype%5D%5B%5D=custom_event"
  end

  test "#call should link the user to the admin filter" do
    event = create(:event, user: user)

    result = render_entry(event)

    link = result.css("a[data-key='events.user']").first
    assert_not_nil link
    assert_equal "##{user.id}", link.text
    assert_includes link["href"], "filter%5Buser_id%5D=#{user.id}"
    assert_includes result.text, "User:"
  end

  test "#call should reveal the user email on hover" do
    event = create(:event, user: user)

    result = render_entry(event)

    link = result.css("a[data-key='events.user']").first
    assert_equal user.email_address, link["title"]
  end

  test "#call should link the subject to the admin filter" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", subject: feed, user: user)

    result = render_entry(event)

    link = result.css("a[data-key='events.subject']").first
    assert_not_nil link
    assert_equal "Feed##{feed.id}", link.text
    assert_includes link["href"], "/admin/events"
    assert_includes link["href"], "filter%5Bsubject_type%5D=Feed"
    assert_includes link["href"], "filter%5Bsubject_id%5D=#{feed.id}"
    assert_includes result.text, "Target:"
  end

  test "#call should reveal the subject name on hover" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", subject: feed, user: user)

    result = render_entry(event)

    link = result.css("a[data-key='events.subject']").first
    assert_equal feed.display_name, link["title"]
  end

  test "#call should omit the subject hover title when the subject is gone" do
    event = create(:event, user: user)
    event.update!(subject_type: "Feed", subject_id: 12_345)

    result = render_entry(event)

    link = result.css("a[data-key='events.subject']").first
    assert_not_nil link
    assert_nil link["title"]
  end

  test "#call should show System for events without a user" do
    event = create(:event, user: nil)

    result = render_entry(event)

    label = result.css("[data-key='events.user']").first
    assert_not_nil label
    assert_equal "System", label.text
  end

  test "#call should omit the target for events without a subject" do
    event = create(:event, user: user)

    result = render_entry(event)

    assert_empty result.css("[data-key='events.subject']")
    assert_not_includes result.text, "Target:"
  end

  test "#call should truncate the footer on narrow screens" do
    event = create(:event, user: user)

    result = render_entry(event)

    footer = result.css("[data-key='events.timestamp']").first.parent
    assert_includes footer["class"], "truncate"
  end
end
