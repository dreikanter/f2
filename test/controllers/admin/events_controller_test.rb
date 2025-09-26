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
    assert_select "td", "TestEvent"
  end

  test "should allow admin users to view event details" do
    login_as(admin_user)
    event = create(:event, type: "TestEvent", message: "Test message")

    get admin_event_path(event)

    assert_response :success
    assert_select "h1", "Event ##{event.id}"
    assert_select "dd", "TestEvent"
  end

  test "should paginate events" do
    login_as(admin_user)

    # Create 30 events (more than per_page of 25)
    30.times do |i|
      create(:event, type: "Event#{i}")
    end

    get admin_events_path

    assert_response :success
    assert_select ".pagination"
    assert_select "tbody tr", count: 25 # Should show 25 event rows per page
  end

  test "should show empty state when no events exist" do
    login_as(admin_user)

    get admin_events_path

    assert_response :success
    assert_select "h1", "Events"
    assert_select "table", count: 0 # No table should be rendered
    assert_select "h4", "No events found"
    assert_select "p", "Events will appear here as they are created."
  end

  test "should filter events by type" do
    login_as(admin_user)

    event1 = create(:event, type: "TypeA", message: "Event A")
    event2 = create(:event, type: "TypeB", message: "Event B")
    event3 = create(:event, type: "TypeA", message: "Another A")

    get admin_events_path, params: { filter_query: { type: "TypeA" }.to_json }

    assert_response :success
    assert_select "tbody tr", count: 2 # Should show 2 TypeA events
    assert_select "td", text: "TypeA", count: 2
    assert_select "td", text: "TypeB", count: 0
  end

  test "should filter events by subject_type" do
    login_as(admin_user)
    test_user = create(:user, email_address: "test_user_#{rand(10000)}@example.com")
    feed = create(:feed, user: test_user)

    event1 = create(:event, type: "Event1", subject: test_user)
    event2 = create(:event, type: "Event2", subject: feed)
    event3 = create(:event, type: "Event3", subject: test_user)

    get admin_events_path, params: { filter_query: { subject_type: "User" }.to_json }

    assert_response :success
    assert_select "tbody tr", count: 2 # Should show 2 User events
    assert_select "a[href*='subject_type']", text: "User", count: 2
    assert_select "a[href*='subject_type']", text: "Feed", count: 0
  end

  test "should show reset filter button when filter is active" do
    login_as(admin_user)
    create(:event, type: "TestEvent")

    get admin_events_path, params: { filter_query: { type: "TestEvent" }.to_json }

    assert_response :success
    assert_select "a", text: "Reset Filter"
  end

  test "should not show reset filter button when no filter is active" do
    login_as(admin_user)
    create(:event, type: "TestEvent")

    get admin_events_path

    assert_response :success
    assert_select "a", text: "Reset Filter", count: 0
  end

  test "should handle invalid filter_query parameter gracefully" do
    login_as(admin_user)
    create(:event, type: "TestEvent")

    get admin_events_path, params: { filter_query: "invalid json" }

    assert_response :success
    assert_select "tbody tr", count: 1 # Should show all events
  end

  test "should preserve filter in pagination links" do
    login_as(admin_user)

    # Create 30 events of the same type
    30.times do |i|
      create(:event, type: "FilteredType", message: "Event #{i}")
    end

    get admin_events_path, params: { filter_query: { type: "FilteredType" }.to_json }

    assert_response :success
    assert_select ".pagination a[href*='filter_query']", minimum: 1
  end

  private

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end
end
