require "test_helper"

class Admin::EventsControllerTest < ActionDispatch::IntegrationTest
  def admin_user
    @admin_user ||= begin
      user = create(:user)
      create(:permission, user: user, name: "admin")
      user
    end
  end

  def regular_user
    @regular_user ||= create(:user)
  end

  test "should redirect non-admin users" do
    login_as(regular_user)

    get admin_events_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "should redirect unauthenticated users" do
    get admin_events_path

    assert_redirected_to new_session_path
  end

  test "should allow admin users to view events index" do
    login_as(admin_user)
    user = create(:user)
    create(:event, type: "TestEvent", message: "Test message", user: user)

    get admin_events_path

    assert_response :success
    assert_select "h1", "Events Log"
    assert_select '[data-key="events.type"]', "TestEvent"
    assert_select 'a[data-key="events.user"]', "##{user.id}"
  end

  test "should allow admin users to view event details" do
    login_as(admin_user)
    event = create(:event, type: "TestEvent", message: "Test message", user: create(:user))

    get admin_event_path(event)

    assert_response :success
    assert_select "h1", "Event ##{event.id}"
    assert_select '[data-key="admin.events.type"]', "TestEvent"
    assert_select "a[data-key='admin.event.user']", "User ##{event.user_id}"
  end

  test "should list imported posts referenced by the event" do
    login_as(admin_user)
    feed = create(:feed)
    event = create(:event, type: "feed_refresh", subject: feed, user: feed.user)
    post = create(:post, feed: feed)
    create(:event_reference, event: event, reference: post)

    get admin_event_path(event)

    assert_response :success
    assert_select "[data-key='events.imported_posts']"
    assert_select "##{ActionView::RecordIdentifier.dom_id(post)}"
  end

  test "should link user subject to filter by that subject" do
    login_as(admin_user)
    subject_user = create(:user)
    event = create(:event, subject: subject_user)

    get admin_event_path(event)

    assert_response :success
    assert_select "a[data-key='admin.event.subject.type'][href*='filter%5Bsubject_type%5D=User']", text: "User"
    assert_select "a[data-key='admin.event.subject.type'][href*='filter%5Bsubject_id%5D=#{subject_user.id}']", text: "User"
  end

  test "should render the most recent page of events" do
    with_page_size(2) do
      login_as(admin_user)
      3.times { |i| create(:event, type: "Event#{i}") }

      get admin_events_path

      assert_response :success
      assert_select "#events_log"
      assert_select '[data-key="events.timestamp"]', count: 2
      assert_select '[data-key="events.type"]', count: 2
    end
  end

  test "should show empty state when no events exist" do
    login_as(admin_user)

    get admin_events_path

    assert_response :success
    assert_select "h1", "Events Log"
    assert_select '[data-key="empty-state"]'
    assert_select "p", "No events to show yet"
  end

  test "should poll on the first page only" do
    with_page_size(2) do
      login_as(admin_user)
      3.times { |i| create(:event, type: "Event#{i}") }

      get admin_events_path
      assert_response :success
      assert_select "#events_log[data-controller='polling']"
      assert_select "[data-key='events.refresh']"
      assert_select "[data-key='events.older']"
      assert_select "a[data-key='events.newer']", count: 0
    end
  end

  test "should browse older pages with a stable cursor" do
    with_page_size(2) do
      login_as(admin_user)
      events = Array.new(5) { |i| create(:event, type: "Event#{i}") }
      oldest_on_first_page = events[3]

      get admin_events_path, params: { before: oldest_on_first_page.id }
      assert_response :success
      # Older page is static history: no polling, but offers Newer + Older.
      assert_select "#events_log[data-controller='polling']", count: 0
      assert_select "[data-key='events.refresh']", count: 0
      assert_select "[data-key='events.newer']"
      assert_select "[data-key='events.older']"
      assert_select '[data-key="events.type"]', count: 2
    end
  end

  test "should resume polling when newer navigation reaches the head" do
    with_page_size(2) do
      login_as(admin_user)
      events = Array.new(4) { |i| create(:event, type: "Event#{i}") }

      # after the 2nd-oldest id returns the newest two events (the head)
      get admin_events_path, params: { after: events[1].id }

      assert_response :success
      assert_select "#events_log[data-controller='polling']"
      assert_select "[data-key='events.refresh']"
      assert_select "a[data-key='events.newer']", count: 0
    end
  end

  test "should redirect to the latest page when a cursor matches no events" do
    with_page_size(2) do
      login_as(admin_user)
      event = create(:event)

      get admin_events_path, params: { before: event.id }

      assert_redirected_to admin_events_path
    end
  end

  test "should not drift older pages when new events arrive" do
    with_page_size(2) do
      login_as(admin_user)
      older = [create(:event, type: "Old0"), create(:event, type: "Old1")]
      boundary = create(:event, type: "Boundary")
      create(:event, type: "Newer0")
      create(:event, type: "Newer1")

      # Page anchored before the boundary id stays the same regardless of newer rows.
      get admin_events_path, params: { before: boundary.id }
      assert_response :success
      assert_select '[data-key="events.type"]', text: "Old1", count: 1
      assert_select '[data-key="events.type"]', text: "Old0", count: 1
      assert_select '[data-key="events.type"]', text: "Newer0", count: 0
      assert_equal [older.last.id, older.first.id].max, older.map(&:id).max
    end
  end

  test "should render admin events turbo stream" do
    login_as(admin_user)
    event = create(:event, type: "NewAdminEvent")

    get admin_events_path(format: :turbo_stream), params: { after_id: event.id - 1 }

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_includes response.body, "events_log"
    assert_includes response.body, "NewAdminEvent"
  end

  test "should return empty admin turbo stream when there are no new events" do
    login_as(admin_user)
    event = create(:event)

    get admin_events_path(format: :turbo_stream), params: { after_id: event.id }

    assert_response :success
    assert_empty response.body
  end

  test "should refresh only the first page when polling" do
    with_page_size(2) do
      login_as(admin_user)
      3.times { |i| create(:event, type: "admin_event_#{i}") }

      get admin_events_path(format: :turbo_stream), params: { after_id: 0 }

      assert_response :success
      assert_select "[data-key='events.type']", count: 2
      assert_select "#events_log[data-controller='polling']"
    end
  end

  test "should show recorded subject when subject missing" do
    login_as(admin_user)
    event = create(:event, type: "MissingSubjectEvent", subject: nil)
    event.update!(subject_type: "Post", subject_id: 42)

    get admin_events_path

    assert_response :success
    assert_select '[data-key="events.subject"]', text: "Post#42"
  end

  test "should filter events by subject_type" do
    login_as(admin_user)
    test_user = create(:user, email_address: "test_user_#{SecureRandom.uuid}@example.com")
    feed = create(:feed, user: test_user)

    create(:event, type: "Event1", subject: test_user)
    create(:event, type: "Event2", subject: feed)
    create(:event, type: "Event3", subject: test_user)

    get admin_events_path, params: { filter: { subject_type: "User" } }

    assert_response :success
    assert_select '[data-key="events.type"]', count: 2
    assert_select '[data-key="events.subject"]', text: /User#/, count: 2
    assert_select '[data-key="events.subject"]', text: /Feed#/, count: 0
  end

  test "should filter events by subject_id" do
    login_as(admin_user)
    test_user = create(:user, email_address: "test_user_#{SecureRandom.uuid}@example.com")
    feed1 = create(:feed, user: test_user, url: "https://example1.com/feed")
    feed2 = create(:feed, user: test_user, url: "https://example2.com/feed")

    create(:event, type: "Event1", subject: feed1)
    create(:event, type: "Event2", subject: feed2)
    create(:event, type: "Event3", subject: feed1)

    get admin_events_path, params: { filter: { subject_type: "Feed", subject_id: feed1.id } }

    assert_response :success
    assert_select '[data-key="events.type"]', count: 2
  end

  test "should handle invalid filter parameter gracefully" do
    login_as(admin_user)
    create(:event, type: "TestEvent")

    get admin_events_path, params: { filter: { invalid_field: "value" } }

    assert_response :success
    assert_select '[data-key="events.type"]', count: 1 # Should show all events
  end

  test "should filter events by multiple types" do
    login_as(admin_user)

    create(:event, type: "TypeA", message: "Event A")
    create(:event, type: "TypeB", message: "Event B")
    create(:event, type: "TypeC", message: "Event C")
    create(:event, type: "TypeA", message: "Another A")

    get admin_events_path, params: { filter: { type: %w[TypeA TypeB] } }

    assert_response :success
    assert_select '[data-key="events.type"]', count: 3
    assert_select '[data-key="events.type"]', text: "TypeA", count: 2
    assert_select '[data-key="events.type"]', text: "TypeB", count: 1
    assert_select '[data-key="events.type"]', text: "TypeC", count: 0
  end

  test "should filter events by level" do
    login_as(admin_user)

    create(:event, type: "InfoEvent", level: :info)
    create(:event, type: "WarningEvent", level: :warning)

    get admin_events_path, params: { filter: { level: "warning" } }

    assert_response :success
    assert_select '[data-key="events.type"]', text: "WarningEvent", count: 1
    assert_select '[data-key="events.type"]', text: "InfoEvent", count: 0
  end

  test "should filter events by user_id" do
    login_as(admin_user)

    user1 = create(:user)
    user2 = create(:user)

    create(:event, type: "Event1", user: user1)
    create(:event, type: "Event2", user: user2)
    create(:event, type: "Event3", user: user1)

    get admin_events_path, params: { filter: { user_id: user1.id } }

    assert_response :success
    assert_select '[data-key="events.type"]', count: 2
  end

  test "should filter events by user_id and multiple types" do
    login_as(admin_user)

    user1 = create(:user)
    user2 = create(:user)

    create(:event, type: "EmailBouncedEvent", user: user1)
    create(:event, type: "EmailFailedEvent", user: user1)
    create(:event, type: "EmailBouncedEvent", user: user2)
    create(:event, type: "OtherEvent", user: user1)

    get admin_events_path, params: { filter: { user_id: user1.id, type: %w[EmailBouncedEvent EmailFailedEvent] } }

    assert_response :success
    assert_select '[data-key="events.type"]', count: 2
  end

  test "should include filter params in polling endpoint" do
    login_as(admin_user)

    user1 = create(:user)

    4.times { create(:event, type: "TypeA", user: user1) }
    2.times { create(:event, type: "TypeB", user: user1) }

    get admin_events_path, params: { filter: { type: ["TypeA"] } }

    assert_response :success
    assert_select '[data-key="events.type"]', count: 4
    assert_select "#events_log[data-polling-endpoint-value*='filter']"
    assert_select "#events_log[data-polling-endpoint-value*='TypeA']"
  end

  private

  def with_page_size(size)
    original = Admin::EventsController.events_page_size
    Admin::EventsController.events_page_size = size
    yield
  ensure
    Admin::EventsController.events_page_size = original
  end

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end
end
