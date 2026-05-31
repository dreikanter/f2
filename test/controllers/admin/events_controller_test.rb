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
    assert_select "h1", "Events"
    assert_select '[data-key="admin.events.type"]', "TestEvent"
    assert_select 'a[data-key="admin.events.user"]', "User ##{user.id}"
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

  test "should link user subject to filter by that subject" do
    login_as(admin_user)
    subject_user = create(:user)
    event = create(:event, subject: subject_user)

    get admin_event_path(event)

    assert_response :success
    assert_select "a[data-key='admin.event.subject.type'][href*='filter%5Bsubject_type%5D=User']", text: "User"
    assert_select "a[data-key='admin.event.subject.type'][href*='filter%5Bsubject_id%5D=#{subject_user.id}']", text: "User"
  end

  test "should render the most recent events up to the initial limit" do
    with_event_limits(initial: 2) do
      login_as(admin_user)
      3.times { |i| create(:event, type: "Event#{i}") }

      get admin_events_path

      assert_response :success
      assert_select "#admin_events_log"
      assert_select '[data-key="admin.events.timestamp"]', count: 2
      assert_select '[data-key="admin.events.type"]', count: 2
    end
  end

  test "should show empty state when no events exist" do
    login_as(admin_user)

    get admin_events_path

    assert_response :success
    assert_select "h1", "Events"
    assert_select '[data-key="admin.events.table"]', count: 0 # No table should be rendered
    assert_select '[data-key="empty-state"]'
    assert_select "p", "No events to show yet"
  end

  test "should render admin events turbo stream" do
    login_as(admin_user)
    event = create(:event, type: "NewAdminEvent")

    get admin_events_path(format: :turbo_stream), params: { after_id: event.id - 1 }

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_includes response.body, "admin_events_log"
    assert_includes response.body, "NewAdminEvent"
  end

  test "should return empty admin turbo stream when there are no new events" do
    login_as(admin_user)
    event = create(:event)

    get admin_events_path(format: :turbo_stream), params: { after_id: event.id }

    assert_response :success
    assert_empty response.body
  end

  test "should cap admin turbo stream events at the stream limit" do
    with_event_limits(stream: 2) do
      login_as(admin_user)
      3.times { |i| create(:event, type: "admin_event_#{i}") }

      get admin_events_path(format: :turbo_stream), params: { after_id: 0 }

      assert_response :success
      assert_select "[data-key='admin.events.type']", count: 2
    end
  end

  test "should show recorded subject when subject missing" do
    login_as(admin_user)
    event = create(:event, type: "MissingSubjectEvent", subject: nil)
    event.update!(subject_type: "Post", subject_id: 42)

    get admin_events_path

    assert_response :success
    assert_select '[data-key="admin.events.subject"]', text: "Post #42"
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
    assert_select '[data-key="admin.events.type"]', count: 2
    assert_select '[data-key="admin.events.subject"]', text: /User #/, count: 2
    assert_select '[data-key="admin.events.subject"]', text: /Feed #/, count: 0
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
    assert_select '[data-key="admin.events.type"]', count: 2
  end

  test "should handle invalid filter parameter gracefully" do
    login_as(admin_user)
    create(:event, type: "TestEvent")

    get admin_events_path, params: { filter: { invalid_field: "value" } }

    assert_response :success
    assert_select '[data-key="admin.events.type"]', count: 1 # Should show all events
  end

  test "should filter events by multiple types" do
    login_as(admin_user)

    create(:event, type: "TypeA", message: "Event A")
    create(:event, type: "TypeB", message: "Event B")
    create(:event, type: "TypeC", message: "Event C")
    create(:event, type: "TypeA", message: "Another A")

    get admin_events_path, params: { filter: { type: %w[TypeA TypeB] } }

    assert_response :success
    assert_select '[data-key="admin.events.type"]', count: 3
    assert_select '[data-key="admin.events.type"]', text: "TypeA", count: 2
    assert_select '[data-key="admin.events.type"]', text: "TypeB", count: 1
    assert_select '[data-key="admin.events.type"]', text: "TypeC", count: 0
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
    assert_select '[data-key="admin.events.type"]', count: 2
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
    assert_select '[data-key="admin.events.type"]', count: 2
  end

  test "should include filter params in polling endpoint" do
    login_as(admin_user)

    user1 = create(:user)

    4.times { create(:event, type: "TypeA", user: user1) }
    2.times { create(:event, type: "TypeB", user: user1) }

    get admin_events_path, params: { filter: { type: ["TypeA"] } }

    assert_response :success
    assert_select '[data-key="admin.events.type"]', count: 4
    assert_select "#admin_events_log[data-polling-endpoint-value*='filter']"
    assert_select "#admin_events_log[data-polling-endpoint-value*='TypeA']"
  end

  private

  def with_event_limits(initial: Admin::EventsController.initial_events_limit, stream: Admin::EventsController.stream_events_limit)
    original_initial = Admin::EventsController.initial_events_limit
    original_stream = Admin::EventsController.stream_events_limit
    Admin::EventsController.initial_events_limit = initial
    Admin::EventsController.stream_events_limit = stream
    yield
  ensure
    Admin::EventsController.initial_events_limit = original_initial
    Admin::EventsController.stream_events_limit = original_stream
  end

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end
end
