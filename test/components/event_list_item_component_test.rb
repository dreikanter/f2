require "test_helper"

class EventListItemComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def render_item(event, href: nil)
    href ||= "/events/#{event.id}"
    render_inline(EventListItemComponent.new(event: event, href: href))
  end

  # --- Shared presentation (both modes) ---

  test "#call should render description, timestamp link and identity hooks" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_item(event)

    item = result.css("[data-key='events.entry']").first
    assert_not_nil item
    assert_equal "feed_refresh", item["data-event-type"]
    assert_equal event.id.to_s, item["data-event-id"]
    assert_not_nil result.css("[data-key='events.description']").first
    assert_not_nil result.css("a[data-key='events.timestamp'][href='/events/#{event.id}']").first
  end

  test "#call should place the timestamp after the description in the top section" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_item(event)

    row = result.at_css("[data-key='events.description']").parent
    keys = row.css("> *").map { |node| node["data-key"] }
    assert_operator keys.index("events.description"), :<, keys.index("events.timestamp")
  end

  test "#call should render the description at the default text size" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_item(event)

    description = result.css("[data-key='events.description']").first
    assert_not_includes description["class"], "text-sm"
  end

  test "#call should flag error events with a red cross icon" do
    event = create(:event, type: "error_event", level: :error, user: user)

    result = render_item(event)

    icon = result.at_css("[data-key='events.severity'] svg")
    assert_not_nil icon
    assert_includes icon["class"], "text-red-500"
  end

  test "#call should flag warning events with an amber triangle icon" do
    event = create(:event, type: "warning_event", level: :warning, user: user)

    result = render_item(event)

    icon = result.at_css("[data-key='events.severity'] svg")
    assert_not_nil icon
    assert_includes icon["class"], "text-amber-500"
  end

  test "#call should mark routine info events with a light gray info icon" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_item(event)

    icon = result.at_css("[data-key='events.severity'] svg")
    assert_not_nil icon
    assert_includes icon["class"], "text-slate-400"
  end

  test "#call should tint warning rows with the alert palette" do
    event = create(:event, level: :warning, user: user)

    result = render_item(event)

    item = result.css("[data-key='events.entry']").first
    assert_includes item["class"], "bg-amber-50"
    assert_includes item["class"], "hover:bg-amber-100"
  end

  test "#call should tint error rows with the alert palette" do
    event = create(:event, level: :error, user: user)

    result = render_item(event)

    item = result.css("[data-key='events.entry']").first
    assert_includes item["class"], "bg-red-100"
    assert_includes item["class"], "hover:bg-red-200"
  end

  test "#call should keep routine rows neutral" do
    event = create(:event, level: :info, user: user)

    result = render_item(event)

    item = result.css("[data-key='events.entry']").first
    assert_includes item["class"], "bg-white"
  end

  # --- Simplified mode ---

  test "#call should not render a footer in simplified mode" do
    event = create(:event, type: "feed_refresh", user: user)

    result = render_item(event)

    assert_empty result.css("[data-key='events.footer']")
    assert_empty result.css("[data-key='events.type']")
  end

  test "#call should render the severity as a plain marker in simplified mode" do
    event = create(:event, level: :error, user: user)

    result = render_item(event)

    assert_empty result.css("a[data-key='events.severity']")
    assert_not_nil result.css("span[data-key='events.severity']").first
  end

  test "#call should not nest the description's links inside the detail link" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", subject: feed, user: user)

    result = render_item(event)

    detail = result.css("a[href='/events/#{event.id}']")
    assert_equal 1, detail.size
    assert_equal "events.timestamp", detail.first["data-key"]
    assert_empty result.css("a[href='/events/#{event.id}'] a")
  end

  # --- Extended (admin) mode ---

  def render_admin_item(event)
    render_inline(Admin::EventListItemComponent.new(event: event, href: "/admin/events/#{event.id}"))
  end

  test "#call should render a footer with type, user and target in extended mode" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", subject: feed, user: user)

    result = render_admin_item(event)

    assert_not_nil result.css("[data-key='events.footer']").first
    assert_not_nil result.css("[data-key='events.type']").first
    assert_includes result.text, "User:"
    assert_includes result.text, "Target:"
  end

  test "#call should link the severity icon to the level filter in extended mode" do
    event = create(:event, level: :error, user: user)

    result = render_admin_item(event)

    link = result.css("a[data-key='events.severity']").first
    assert_not_nil link
    assert_includes link["href"], "/admin/events"
    assert_includes link["href"], "filter%5Blevel%5D=error"
    assert_equal "Show error events", link["title"]
  end

  test "#call should keep the timestamp in the top section in extended mode" do
    event = create(:event, user: user)

    result = render_admin_item(event)

    link = result.css("a[data-key='events.timestamp']").first
    assert_not_nil link
    assert_equal "/admin/events/#{event.id}", link["href"]
    # The timestamp now lives in the top row, not the footer divider.
    assert_not_includes link.parent["class"].to_s, "border-t"
  end

  test "#call should link the type to the admin filter" do
    event = create(:event, type: "custom_event", user: user)

    result = render_admin_item(event)

    link = result.css("a[data-key='events.type']").first
    assert_equal "custom_event", link.text
    assert_includes link["href"], "filter%5Btype%5D%5B%5D=custom_event"
    assert_includes result.css("[data-key='events.footer']").text, "Type: custom_event"
  end

  test "#call should link the user to the admin filter and reveal the email on hover" do
    event = create(:event, user: user)

    result = render_admin_item(event)

    link = result.css("a[data-key='events.user']").first
    assert_equal "##{user.id}", link.text
    assert_includes link["href"], "filter%5Buser_id%5D=#{user.id}"
    assert_equal user.email_address, link["title"]
  end

  test "#call should show System for events without a user in extended mode" do
    event = create(:event, user: nil)

    result = render_admin_item(event)

    label = result.css("[data-key='events.user']").first
    assert_equal "System", label.text
  end

  test "#call should link the subject to the admin filter and reveal its name on hover" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", subject: feed, user: user)

    result = render_admin_item(event)

    link = result.css("a[data-key='events.subject']").first
    assert_equal "Feed##{feed.id}", link.text
    assert_includes link["href"], "filter%5Bsubject_type%5D=Feed"
    assert_includes link["href"], "filter%5Bsubject_id%5D=#{feed.id}"
    assert_equal feed.display_name, link["title"]
  end

  test "#call should omit the subject hover title when the subject is gone" do
    event = create(:event, user: user)
    event.update!(subject_type: "Feed", subject_id: 12_345)

    result = render_admin_item(event)

    link = result.css("a[data-key='events.subject']").first
    assert_not_nil link
    assert_nil link["title"]
  end

  test "#call should omit the target for events without a subject" do
    event = create(:event, user: user)

    result = render_admin_item(event)

    assert_empty result.css("[data-key='events.subject']")
    assert_not_includes result.text, "Target:"
  end

  test "#call should render the extended footer as a borderless muted line" do
    event = create(:event, level: :error, user: user)

    result = render_admin_item(event)

    footer = result.css("[data-key='events.footer']").first
    assert_not_nil footer
    assert_not_includes footer["class"].to_s, "border-t"
  end
end
