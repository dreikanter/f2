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
    assert_includes response.body, "events_list"
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
      assert_select "[data-key='events.entry']", count: 2
    end
  end

  test "#index should render an HTML page of the user's events" do
    sign_in_as user
    create(:event, type: "my_event", user: user)
    create(:event, type: "someone_elses", user: other_user)

    get events_path

    assert_response :success
    assert_select "h1", "Events Log"
    assert_select "#events_list"
    assert_select '[data-event-type="my_event"]'
    assert_select '[data-event-type="someone_elses"]', count: 0
  end

  test "#index should describe the latest page with a zero offset" do
    sign_in_as user
    create(:event, user: user)

    get events_path

    assert_response :success
    assert_select "[data-key='events.offset']", "Showing the most recent events."
  end

  test "#index should describe the offset when paging into older events" do
    with_page_size(2) do
      sign_in_as user
      events = Array.new(5) { |i| create(:event, type: "Event#{i}", user: user) }

      get events_path, params: { before: events[3].id }

      assert_response :success
      assert_select "[data-key='events.offset']", "2 newer events above what's shown here."
    end
  end

  test "#index should render each event as a card inside the list" do
    sign_in_as user
    create(:event, type: "feed_refresh", user: user)

    get events_path

    assert_response :success
    assert_select "[data-key='events.list'] > [data-key='events.entry']"
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
      assert_select "#events_list[data-controller='polling']", count: 0
      assert_select "[data-key='events.newer']"
      assert_select "[data-key='events.older']"
      assert_select '[data-key="events.entry"]', count: 2
    end
  end

  test "#index should poll on the first page only" do
    with_page_size(2) do
      sign_in_as user
      3.times { |i| create(:event, type: "Event#{i}", user: user) }

      get events_path

      assert_response :success
      assert_select "#events_list[data-controller='polling']"
      assert_select "[data-key='events.older']"
      assert_select "a[data-key='events.newer']", count: 0
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
    assert_select '[data-event-type="mine"]'
    assert_select '[data-event-type="theirs"]', count: 0
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
    assert_select '[data-event-type="my_event"]'
  end

  test "#index should filter user events by type" do
    sign_in_as user
    create(:event, type: "feed_refresh", user: user)
    create(:event, type: "feed_auto_disabled", user: user)
    create(:event, type: "post_withdrawn", user: user)

    get events_path(format: :turbo_stream), params: { after_id: 0, filter: { type: %w[feed_refresh feed_auto_disabled] } }

    assert_response :success
    assert_select "[data-key='events.entry']", count: 2
  end

  test "#index should filter user events by subject_type" do
    sign_in_as user
    feed = create(:feed, user: user)
    create(:event, type: "feed_refresh", subject: feed, user: user)
    create(:event, type: "post_withdrawn", user: user)

    get events_path(format: :turbo_stream), params: { after_id: 0, filter: { subject_type: "Feed" } }

    assert_response :success
    assert_select "[data-key='events.entry']", count: 1
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
    assert_select "#events_list[data-polling-endpoint-value*='feed_refresh']"
  end

  test "#show should render owned event" do
    sign_in_as user
    event = create(:event, type: "owned_event", user: user)

    get event_path(event)

    assert_response :success
    assert_select "h1", "Event ##{event.id}"
  end

  test "#show should list imported posts referenced by the event" do
    sign_in_as user
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", user: user, subject: feed)
    post = create(:post, feed: feed)
    create(:event_reference, event: event, reference: post)

    get event_path(event)

    assert_response :success
    assert_select "[data-key='events.imported_posts']"
    assert_select "##{ActionView::RecordIdentifier.dom_id(post)}"
  end

  test "#show should list imported posts newest first and skip non-post references" do
    sign_in_as user
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", user: user, subject: feed)
    older = create(:post, feed: feed, created_at: 2.days.ago)
    newer = create(:post, feed: feed, created_at: 1.hour.ago)
    create(:event_reference, event: event, reference: older)
    create(:event_reference, event: event, reference: newer)
    create(:event_reference, event: event, reference: user)

    get event_path(event)

    assert_response :success
    newer_dom = ActionView::RecordIdentifier.dom_id(newer)
    older_dom = ActionView::RecordIdentifier.dom_id(older)
    assert_operator response.body.index(newer_dom), :<, response.body.index(older_dom)
  end

  test "#show should limit imported posts to MAX_RECENT_POSTS" do
    sign_in_as user
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", user: user, subject: feed)
    posts = create_list(:post, EventsController::MAX_RECENT_POSTS + 2, feed: feed)
    posts.each { |post| create(:event_reference, event: event, reference: post) }

    get event_path(event)

    assert_response :success
    rendered = posts.count { |post| css_select("##{ActionView::RecordIdentifier.dom_id(post)}").any? }
    assert_equal EventsController::MAX_RECENT_POSTS, rendered
  end

  test "#show should not render the imported posts section without references" do
    sign_in_as user
    event = create(:event, type: "feed_refresh", user: user)

    get event_path(event)

    assert_response :success
    assert_select "[data-key='events.imported_posts']", false
  end

  test "#show should list the AI calls referenced by the event" do
    sign_in_as user
    feed = create(:feed, user: user)
    event = create(:event, type: "feed_refresh", user: user, subject: feed)
    usage = create(:llm_usage, user: user, feed: feed, model: "claude-sonnet-4-6", cost_estimate_cents: 3)
    create(:event_reference, event: event, reference: usage)

    get event_path(event)

    assert_response :success
    assert_select "[data-key='events.ai_usage']"
    assert_select "[data-llm-usage-id='#{usage.id}']"
    assert_select "[data-key='events.llm_usage.model']", text: "claude-sonnet-4-6"
  end

  test "#show should not render the AI usage section without references" do
    sign_in_as user
    event = create(:event, type: "feed_refresh", user: user)

    get event_path(event)

    assert_response :success
    assert_select "[data-key='events.ai_usage']", false
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
    assert_select "a[href='#{event_path(older)}']", text: "← Previous"
    assert_select "a[href='#{event_path(newer)}']", text: "Next →"
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

  test "#index should preload imported post counts for the full polling stream" do
    sign_in_as user
    feed = create(:feed, user: user)
    3.times do
      refresh = create(:event, type: "feed_refresh", user: user, subject: feed)
      create(:event_reference, event: refresh, reference: create(:post, feed: feed))
    end

    queries = count_queries(/\bevent_references\b/) do
      get events_path(format: :turbo_stream), params: { after_id: 0 }
    end

    assert_response :success
    assert_operator queries, :<=, 1, "event_references should be preloaded in a single query, not one per row"
  end

  private

  # Counts the application SQL queries matching pattern run during the block.
  def count_queries(pattern)
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) do
      count += 1 if payload[:sql] =~ pattern && !payload[:name].to_s.include?("SCHEMA")
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  def with_page_size(size)
    original = EventsController.events_page_size
    EventsController.events_page_size = size
    yield
  ensure
    EventsController.events_page_size = original
  end
end
