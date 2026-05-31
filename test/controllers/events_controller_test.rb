require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  test "#index should require authentication" do
    get events_path(format: :turbo_stream)

    assert_redirected_to new_session_path
  end

  test "#index should render new user events as turbo stream" do
    sign_in_as user
    create(:event, type: "old_event", user: user)
    event = create(:event, type: "new_event", user: user)
    create(:event, type: "other_event", user: other_user)

    get events_path(format: :turbo_stream), params: { after_id: event.id - 1 }

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_includes response.body, "events_log"
    assert_includes response.body, "new_event"
    assert_not_includes response.body, "other_event"
  end

  test "#index should return empty turbo stream when there are no new events" do
    sign_in_as user
    event = create(:event, user: user)

    get events_path(format: :turbo_stream), params: { after_id: event.id }

    assert_response :success
    assert_empty response.body
  end

  test "#index should refresh only the first page when polling" do
    with_page_size(2) do
      sign_in_as user
      3.times { |i| create(:event, type: "event_#{i}", user: user) }

      get events_path(format: :turbo_stream), params: { after_id: 0 }

      assert_response :success
      assert_select "[data-key='events.type']", count: 2
    end
  end

  test "#index should render an HTML page of the user's events" do
    sign_in_as user
    create(:event, type: "my_event", user: user)
    create(:event, type: "someone_elses", user: other_user)

    get events_path

    assert_response :success
    assert_select "h1", "Events"
    assert_select "#events_log"
    assert_select '[data-key="events.type"]', text: "my_event"
    assert_select '[data-key="events.type"]', text: "someone_elses", count: 0
  end

  test "#index should order by created_at, not insertion id" do
    sign_in_as user
    # Insertion (id) order deliberately differs from chronological order.
    create(:event, type: "middle", user: user, created_at: 2.days.ago)
    create(:event, type: "newest", user: user, created_at: 1.hour.ago)
    create(:event, type: "oldest", user: user, created_at: 5.days.ago)

    get events_path
    body = response.body

    assert body.index("newest") < body.index("middle"), "newest should precede middle"
    assert body.index("middle") < body.index("oldest"), "middle should precede oldest"
  end

  test "#index should keep cursor pages chronological across a backdated event" do
    with_page_size(2) do
      sign_in_as user
      newest = create(:event, type: "newest", user: user, created_at: 1.hour.ago)
      second = create(:event, type: "second", user: user, created_at: 2.hours.ago)
      # Higher id but older timestamp: must land on a later page, not the first.
      create(:event, type: "backdated", user: user, created_at: 10.days.ago)

      get events_path
      body = response.body
      assert_includes body, "newest"
      assert_includes body, "second"
      assert_not_includes body, "backdated"

      # Older page (before the oldest shown) surfaces the backdated event.
      get events_path, params: { before: second.id }
      assert_includes response.body, "backdated"
      assert_not_nil newest
    end
  end

  test "#index should browse older user events with a stable cursor" do
    with_page_size(2) do
      sign_in_as user
      events = Array.new(5) { |i| create(:event, type: "Event#{i}", user: user) }
      oldest_on_first_page = events[3]

      get events_path, params: { before: oldest_on_first_page.id }

      assert_response :success
      assert_select "#events_log[data-controller='polling']", count: 0
      assert_select "[data-key='events.newer']"
      assert_select "[data-key='events.older']"
      assert_select '[data-key="events.type"]', count: 2
    end
  end

  test "#index should poll on the first page only" do
    with_page_size(2) do
      sign_in_as user
      3.times { |i| create(:event, type: "Event#{i}", user: user) }

      get events_path

      assert_response :success
      assert_select "#events_log[data-controller='polling']"
      assert_select "[data-key='events.older']"
      assert_select "[data-key='events.newer']", count: 0
    end
  end

  test "#index should not expose another user's events through a cursor" do
    sign_in_as user
    create(:event, type: "mine", user: user)
    theirs = create(:event, type: "theirs", user: other_user)

    # A cursor pointing at another user's (newer) event must not leak it; only
    # the current user's older events surface.
    get events_path, params: { before: theirs.id }

    assert_response :success
    assert_select '[data-key="events.type"]', text: "mine"
    assert_select '[data-key="events.type"]', text: "theirs", count: 0
  end

  test "#index should redirect to the latest page when a cursor matches no events" do
    sign_in_as user
    event = create(:event, user: user)

    get events_path, params: { before: event.id }

    assert_redirected_to events_path
  end

  test "#index should ignore a malformed filter param" do
    sign_in_as user
    create(:event, type: "my_event", user: user)

    get events_path, params: { filter: "bad" }

    assert_response :success
    assert_select '[data-key="events.type"]', text: "my_event"
  end

  test "#index should filter user events by type" do
    sign_in_as user
    create(:event, type: "feed_refresh", user: user)
    create(:event, type: "feed_refresh_error", user: user)
    create(:event, type: "post_withdrawn", user: user)

    get events_path(format: :turbo_stream), params: { after_id: 0, filter: { type: %w[feed_refresh feed_refresh_error] } }

    assert_response :success
    assert_select "[data-key='events.type']", count: 2
  end

  test "#index should filter user events by subject_type" do
    sign_in_as user
    feed = create(:feed, user: user)
    create(:event, type: "feed_refresh", subject: feed, user: user)
    create(:event, type: "post_withdrawn", user: user)

    get events_path(format: :turbo_stream), params: { after_id: 0, filter: { subject_type: "Feed" } }

    assert_response :success
    assert_select "[data-key='events.type']", count: 1
  end

  test "#index should not leak other users' events through filters" do
    sign_in_as user
    create(:event, type: "feed_refresh", user: other_user)

    get events_path(format: :turbo_stream), params: { after_id: 0, filter: { user_id: other_user.id } }

    assert_response :success
    assert_empty response.body
  end

  test "#index should carry the active filter into the polling endpoint" do
    sign_in_as user
    create(:event, type: "feed_refresh", user: user)

    get events_path(format: :turbo_stream), params: { after_id: 0, filter: { type: ["feed_refresh"] } }

    assert_response :success
    assert_select "#events_log[data-polling-endpoint-value*='feed_refresh']"
  end

  test "#show should render owned event" do
    sign_in_as user
    event = create(:event, type: "owned_event", user: user)

    get event_path(event)

    assert_response :success
    assert_select "h1", "Event ##{event.id}"
    assert_select "[data-key='events.type']", "owned_event"
  end

  test "#show should render an owned event even with list filter params" do
    sign_in_as user
    event = create(:event, type: "feed_refresh", user: user)

    get event_path(event), params: { filter: { type: ["something_else"] } }

    assert_response :success
    assert_select "h1", "Event ##{event.id}"
  end

  test "#show should not render another user's event" do
    sign_in_as user
    event = create(:event, user: other_user)

    get event_path(event)

    assert_response :not_found
  end

  test "#show should link to the chronologically adjacent events" do
    sign_in_as user
    older = create(:event, type: "older", user: user, created_at: 2.hours.ago)
    current = create(:event, type: "current", user: user, created_at: 1.hour.ago)
    newer = create(:event, type: "newer", user: user, created_at: 10.minutes.ago)

    get event_path(current)

    assert_response :success
    assert_select "a[href='#{event_path(newer)}']", text: "← Previous"
    assert_select "a[href='#{event_path(older)}']", text: "Next →"
  end

  test "#show should disable navigation at the ends of the log" do
    sign_in_as user
    only = create(:event, type: "only", user: user)

    get event_path(only)

    assert_response :success
    assert_select "a", text: "← Previous", count: 0
    assert_select "a", text: "Next →", count: 0
    assert_select "span.cursor-not-allowed", text: "← Previous"
    assert_select "span.cursor-not-allowed", text: "Next →"
  end

  test "#show navigation should ignore another user's events" do
    sign_in_as user
    mine = create(:event, type: "mine", user: user, created_at: 1.hour.ago)
    create(:event, type: "theirs_newer", user: other_user, created_at: 1.minute.ago)
    create(:event, type: "theirs_older", user: other_user, created_at: 2.hours.ago)

    get event_path(mine)

    assert_response :success
    assert_select "span.cursor-not-allowed", text: "← Previous"
    assert_select "span.cursor-not-allowed", text: "Next →"
  end

  private

  def with_page_size(size)
    original = EventsController.events_page_size
    EventsController.events_page_size = size
    yield
  ensure
    EventsController.events_page_size = original
  end
end
