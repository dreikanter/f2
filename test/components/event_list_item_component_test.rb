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
    assert_equal "circle-x", icon["data-icon"]
    assert_includes icon["class"], "text-danger"
  end

  test "#call should flag warning events with an amber triangle icon" do
    event = create(:event, type: "warning_event", level: :warning, user: user)

    result = render_item(event)

    icon = result.at_css("[data-key='events.severity'] svg")
    assert_not_nil icon
    assert_equal "triangle-alert", icon["data-icon"]
    assert_includes icon["class"], "text-warning"
  end

  test "#call should mark routine info events with a light gray info icon" do
    event = create(:event, type: "unconfigured_event", level: :info, user: user)

    result = render_item(event)

    icon = result.at_css("[data-key='events.severity'] svg")
    assert_not_nil icon
    assert_equal "info", icon["data-icon"]
    assert_includes icon["class"], "text-muted"
  end

  test "#call should use the configured icon for the event type" do
    event = create(:event, type: "feed_refresh", level: :info, user: user)

    result = render_item(event)

    icon = result.at_css("[data-key='events.severity'] svg")
    assert_equal "refresh-ccw", icon["data-icon"]
    assert_includes icon["class"], "text-muted"
  end

  test "#call should keep the level color on configured icons" do
    event = create(:event, type: "feed_refresh", level: :error, user: user)

    result = render_item(event)

    icon = result.at_css("[data-key='events.severity'] svg")
    assert_equal "refresh-ccw", icon["data-icon"]
    assert_includes icon["class"], "text-danger"
  end

  test "#call should keep warning rows on the neutral background" do
    event = create(:event, level: :warning, user: user)

    result = render_item(event)

    item = result.css("[data-key='events.entry']").first
    assert_not_includes item["class"], "bg-warning-subtle"
    assert_includes item["class"], "bg-surface"
  end

  test "#call should keep error rows on the neutral background" do
    event = create(:event, level: :error, user: user)

    result = render_item(event)

    item = result.css("[data-key='events.entry']").first
    assert_not_includes item["class"], "bg-danger-subtle"
    assert_includes item["class"], "bg-surface"
  end

  test "#call should keep routine rows neutral" do
    event = create(:event, level: :info, user: user)

    result = render_item(event)

    item = result.css("[data-key='events.entry']").first
    assert_includes item["class"], "bg-surface"
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

  test "#call should render a footer with type, user and subject in extended mode" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", subject: feed, user: user)

    result = render_admin_item(event)

    assert_not_nil result.css("[data-key='events.footer']").first
    assert_not_nil result.css("[data-key='events.type']").first
    assert_includes result.text, "User:"
    assert_includes result.text, "Feed:"
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

  test "#call should render the type as plain text" do
    event = create(:event, type: "custom_event", user: user)

    result = render_admin_item(event)

    label = result.css("span[data-key='events.type']").first
    assert_equal "custom_event", label.text
    assert_empty result.css("a[data-key='events.type']")
    assert_includes result.css("[data-key='events.footer']").text, "Type: custom_event"
  end

  test "#call should link the compact user id to the admin user page" do
    event = create(:event, user: user)

    result = render_admin_item(event)

    link = result.css("a[data-key='events.user']").first
    assert_equal user.id.to_s.last(5), link.text
    assert_equal "/admin/users/#{user.id}", link["href"]
    assert_equal "#{user.id} — #{user.email_address}", link["title"]
    assert_not_includes link["class"], "font-mono"
    assert_not_includes link.text, "#"
  end

  test "#call should show System for events without a user in extended mode" do
    event = create(:event, user: nil)

    result = render_admin_item(event)

    label = result.css("[data-key='events.user']").first
    assert_equal "System", label.text
  end

  test "#call should link only the compact subject id to its application page" do
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", subject: feed, user: user)

    result = render_admin_item(event)

    link = result.css("a[data-key='events.subject']").first
    assert_equal feed.id.to_s.last(5), link.text
    assert_equal "/admin/feeds/#{feed.id}", link["href"]
    assert_equal "#{feed.id} — #{feed.display_name}", link["title"]
    assert_not_includes link["class"], "font-mono"
    assert_not_includes link.text, "#"
    assert_includes result.css("[data-key='events.footer']").text, "Feed: #{feed.id.to_s.last(5)}"
  end

  test "#call should render an orphaned subject as compact plain text" do
    event = create(:event, user: user)
    missing_id = SecureRandom.uuid
    event.update!(subject_type: "Feed", subject_id: missing_id)

    result = render_admin_item(event)

    label = result.css("span[data-key='events.subject']").first
    assert_not_nil label
    assert_equal missing_id.last(5), label.text
    assert_equal missing_id, label["title"]
    assert_empty result.css("a[data-key='events.subject']")
    assert_includes result.css("[data-key='events.footer']").text, "Feed: #{missing_id.last(5)}"
  end

  test "#call should omit the subject for events without one" do
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
