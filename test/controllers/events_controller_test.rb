require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
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

    get events_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "should redirect unauthenticated users" do
    get events_path

    assert_redirected_to new_session_path
  end

  test "should allow admin users to view events index" do
    login_as(admin_user)
    create(:event, type: "TestEvent", message: "Test message")

    get events_path

    assert_response :success
    assert_select "h1", "Events"
    assert_select "td", "TestEvent"
  end

  test "should allow admin users to view event details" do
    login_as(admin_user)
    event = create(:event, type: "TestEvent", message: "Test message")

    get event_path(event)

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

    get events_path

    assert_response :success
    assert_select ".pagination"
    assert_select "tbody tr", count: 25 # Should show 25 event rows per page
  end

  test "should show empty state when no events exist" do
    login_as(admin_user)

    get events_path

    assert_response :success
    assert_select "h1", "Events"
    assert_select "table", count: 0 # No table should be rendered
    assert_select "h4", "No events found"
    assert_select "p", "Events will appear here as they are created."
  end

  private

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end
end
