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

  private

  def with_page_size(size)
    original = EventsController.events_page_size
    EventsController.events_page_size = size
    yield
  ensure
    EventsController.events_page_size = original
  end
end
