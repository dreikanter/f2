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
    assert_includes response.body, "user_events_log"
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

  test "#index should cap turbo stream events at the stream limit" do
    with_stream_events_limit(2) do
      sign_in_as user
      3.times { |i| create(:event, type: "event_#{i}", user: user) }

      get events_path(format: :turbo_stream), params: { after_id: 0 }

      assert_response :success
      assert_select "[data-key='events.type']", count: 2
    end
  end

  test "#show should render owned event" do
    sign_in_as user
    event = create(:event, type: "owned_event", user: user)

    get event_path(event)

    assert_response :success
    assert_select "h1", "Event ##{event.id}"
    assert_select "[data-key='events.type']", "owned_event"
  end

  test "#show should not render another user's event" do
    sign_in_as user
    event = create(:event, user: other_user)

    get event_path(event)

    assert_response :not_found
  end

  private

  def with_stream_events_limit(limit)
    original_limit = EventsController.stream_events_limit
    EventsController.stream_events_limit = limit
    yield
  ensure
    EventsController.stream_events_limit = original_limit
  end
end
