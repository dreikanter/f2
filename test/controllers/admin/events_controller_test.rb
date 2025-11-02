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
    create(:event, type: "TestEvent", message: "Test message")

    get admin_events_path

    assert_response :success
    assert_select "h1", "Events"
    assert_select "code", "TestEvent"
  end

  test "should allow admin users to view event details" do
    login_as(admin_user)
    event = create(:event, type: "TestEvent", message: "Test message")

    get admin_event_path(event)

    assert_response :success
    assert_select "h1", "Event ##{event.id}"
    assert_select "code", "TestEvent"
  end

  test "should link user subject to admin user page" do
    login_as(admin_user)
    subject_user = create(:user)
    event = create(:event, subject: subject_user)

    get admin_event_path(event)

    assert_response :success
    assert_select "a[href='#{admin_user_path(subject_user)}']", text: "User"
  end

  # TBD: Reduce the amount of test records by changing page size
  test "should paginate events" do
    login_as(admin_user)

    # Create 30 events (more than per_page of 25)
    30.times do |i|
      create(:event, type: "Event#{i}")
    end

    get admin_events_path

    assert_response :success
    assert_select "table.ff-table.ff-table--dense"
    assert_select ".ff-event-level", text: "INFO", minimum: 1
    assert_select 'nav[aria-label="Events pagination"]' do
      assert_select "span.text-sm", text: /Showing 25 of 30 events/
      assert_select "ul.inline-flex.items-center"
      assert_select "a", text: "Next"
    end
    assert_select "tbody tr", count: 25 # Should show 25 event rows per page
  end

  test "should show empty state when no events exist" do
    login_as(admin_user)

    get admin_events_path

    assert_response :success
    assert_select "h1", "Events"
    assert_select "table", count: 0 # No table should be rendered
    assert_select "h2", "No events found"
    assert_select "p", "Events will appear here as they are created."
  end

  test "should filter events by subject_type" do
    login_as(admin_user)
    test_user = create(:user, email_address: "test_user_#{SecureRandom.uuid}@example.com")
    feed = create(:feed, user: test_user)

    event1 = create(:event, type: "Event1", subject: test_user)
    event2 = create(:event, type: "Event2", subject: feed)
    event3 = create(:event, type: "Event3", subject: test_user)

    get admin_events_path, params: { filter: { subject_type: "User" } }

    assert_response :success
    assert_select "tbody tr", count: 2
    assert_select "a[href*='subject_type']", text: "User", count: 2
    assert_select "a[href*='subject_type']", text: "Feed", count: 0
  end

  test "should handle invalid filter parameter gracefully" do
    login_as(admin_user)
    create(:event, type: "TestEvent")

    get admin_events_path, params: { filter: { invalid_field: "value" } }

    assert_response :success
    assert_select "tbody tr", count: 1 # Should show all events
  end

  test "should filter events by multiple types" do
    login_as(admin_user)

    event1 = create(:event, type: "TypeA", message: "Event A")
    event2 = create(:event, type: "TypeB", message: "Event B")
    event3 = create(:event, type: "TypeC", message: "Event C")
    event4 = create(:event, type: "TypeA", message: "Another A")

    get admin_events_path, params: { filter: { type: %w[TypeA TypeB] } }

    assert_response :success
    assert_select "tbody tr", count: 3
    assert_select "code", text: "TypeA", count: 2
    assert_select "code", text: "TypeB", count: 1
    assert_select "code", text: "TypeC", count: 0
  end

  test "should filter events by user_id" do
    login_as(admin_user)

    user1 = create(:user)
    user2 = create(:user)

    event1 = create(:event, type: "Event1", user: user1)
    event2 = create(:event, type: "Event2", user: user2)
    event3 = create(:event, type: "Event3", user: user1)

    get admin_events_path, params: { filter: { user_id: user1.id } }

    assert_response :success
    assert_select "tbody tr", count: 2
  end

  test "should filter events by user_id and multiple types" do
    login_as(admin_user)

    user1 = create(:user)
    user2 = create(:user)

    event1 = create(:event, type: "EmailBouncedEvent", user: user1)
    event2 = create(:event, type: "EmailFailedEvent", user: user1)
    event3 = create(:event, type: "EmailBouncedEvent", user: user2)
    event4 = create(:event, type: "OtherEvent", user: user1)

    get admin_events_path, params: { filter: { user_id: user1.id, type: %w[EmailBouncedEvent EmailFailedEvent] } }

    assert_response :success
    assert_select "tbody tr", count: 2
  end

  private

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end
end
