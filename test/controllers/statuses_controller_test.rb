require "test_helper"

class StatusesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  test "#show should require authentication" do
    get status_path
    assert_redirected_to new_session_path
  end

  test "#show should render status when authenticated with no feeds" do
    sign_in_as user
    get status_path
    assert_response :success
    assert_select "h1", "Welcome to Feeder"
  end

  test "#show should render status when authenticated with feeds" do
    sign_in_as user
    create(:feed, user: user)
    get status_path
    assert_response :success
    assert_select "h1", "Status"
  end

  test "#show should display total feeds count" do
    sign_in_as user
    feed1 = create(:feed, user: user)
    feed2 = create(:feed, user: user)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="stats.total_feeds"]').first
    assert_equal "2", css_select('[data-key="stats.total_feeds.value"]').first.text.strip
  end

  test "#show should display total imported posts count" do
    sign_in_as user
    feed = create(:feed, user: user)
    entry1 = create(:feed_entry, feed: feed)
    entry2 = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry1)
    create(:post, feed: feed, feed_entry: entry2)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="stats.total_imported_posts"]').first
    assert_equal "2", css_select('[data-key="stats.total_imported_posts.value"]').first.text.strip
  end

  test "#show should display total published posts count" do
    sign_in_as user
    feed = create(:feed, user: user)
    entry1 = create(:feed_entry, feed: feed)
    entry2 = create(:feed_entry, feed: feed)
    entry3 = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry1, status: :published)
    create(:post, feed: feed, feed_entry: entry2, status: :published)
    create(:post, feed: feed, feed_entry: entry3, status: :draft)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="stats.total_published_posts"]').first
    assert_equal "2", css_select('[data-key="stats.total_published_posts.value"]').first.text.strip
  end

  test "#show should display most recent post publication timestamp" do
    sign_in_as user
    feed = create(:feed, user: user)
    entry = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry, status: :published, published_at: 1.day.ago)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="stats.most_recent_post_publication"]').first
    assert_match(/1d ago/, css_select('[data-key="stats.most_recent_post_publication.value"]').first.text)
  end

  test "#show should hide most recent post publication when no published posts" do
    sign_in_as user

    get status_path
    assert_response :success
    assert css_select('[data-key="stats.most_recent_post_publication"]').empty?
  end

  test "#show should display posts published last week" do
    sign_in_as user
    feed = create(:feed, user: user)
    entry1 = create(:feed_entry, feed: feed)
    entry2 = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry1, published_at: 2.days.ago)
    create(:post, feed: feed, feed_entry: entry2, published_at: 1.day.ago)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="stats.posts_last_week"]').first
    assert_equal "2", css_select('[data-key="stats.posts_last_week.value"]').first.text.strip
  end

  test "#show should hide posts last week when no posts" do
    sign_in_as user

    get status_path
    assert_response :success
    assert css_select('[data-key="stats.posts_last_week"]').empty?
  end

  test "#show should hide post statistics when no posts" do
    sign_in_as user

    get status_path
    assert_response :success
    assert css_select('[data-key="stats.total_imported_posts"]').empty?
    assert css_select('[data-key="stats.total_published_posts"]').empty?
    assert css_select('[data-key="stats.most_recent_post_publication"]').empty?
    assert css_select('[data-key="stats.posts_last_week"]').empty?
  end

  test "#show should render empty state when no feeds" do
    sign_in_as user

    get status_path
    assert_response :success
  end

  test "#show should display statistics when feeds exist" do
    sign_in_as user
    create(:feed, user: user)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="stats.total_feeds"]').first
    assert_equal "1", css_select('[data-key="stats.total_feeds.value"]').first.text.strip
    assert_select "h1", "Status"
  end

  test "#show should display recent user events" do
    sign_in_as user
    create(:feed, user: user)
    event1 = Event.create!(type: "feed_refresh", level: :info, message: "Feed refresh completed", user: user)
    event2 = Event.create!(type: "post_withdrawn", level: :info, message: "Post withdrawn", user: user)

    get status_path
    assert_response :success
    assert_select "h2", "Recent Activity"
    assert_not_nil css_select('[data-key="recent_events.%d"]' % event1.id).first
    assert_not_nil css_select('[data-key="recent_events.%d"]' % event2.id).first
  end

  test "#show should display empty recent events section when no events" do
    sign_in_as user
    create(:feed, user: user)

    get status_path
    assert_response :success
    assert_select "h2", "Recent Activity"
    assert_select '[data-key="empty-state"]'
  end

  test "#show should only display user's own events" do
    other_user = create(:user)
    sign_in_as user
    create(:feed, user: user)
    user_event = Event.create!(type: "feed_refresh", level: :info, message: "User's event", user: user)
    other_event = Event.create!(type: "feed_refresh", level: :info, message: "Other's event", user: other_user)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="recent_events.%d"]' % user_event.id).first
    assert css_select('[data-key="recent_events.%d"]' % other_event.id).empty?
  end

  test "#show should exclude debug level events" do
    sign_in_as user
    create(:feed, user: user)
    info_event = Event.create!(type: "info_event", level: :info, message: "Info event", user: user)
    debug_event = Event.create!(type: "debug_event", level: :debug, message: "Debug event", user: user)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="recent_events.%d"]' % info_event.id).first
    assert css_select('[data-key="recent_events.%d"]' % debug_event.id).empty?
  end

  test "#show should exclude expired events" do
    sign_in_as user
    create(:feed, user: user)
    active_event = Event.create!(type: "active_event", level: :info, message: "Active event", user: user)
    expired_event = Event.create!(type: "expired_event", level: :info, message: "Expired event", user: user, expires_at: 1.hour.ago)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="recent_events.%d"]' % active_event.id).first
    assert css_select('[data-key="recent_events.%d"]' % expired_event.id).empty?
  end

  test "#show should limit recent events to the initial limit" do
    with_initial_events_limit(2) do
      sign_in_as user
      create(:feed, user: user)
      3.times do |i|
        Event.create!(type: "event_#{i}", level: :info, message: "Event #{i}", user: user)
      end

      get status_path
      assert_response :success
      assert_select 'li[data-key^="recent_events."]', count: 2
    end
  end

  test "#show should filter recent events by type" do
    sign_in_as user
    create(:feed, user: user)
    refresh_event = Event.create!(type: "feed_refresh", level: :info, message: "", user: user)
    withdrawn_event = Event.create!(type: "post_withdrawn", level: :info, message: "", user: user)

    get status_path, params: { filter: { type: ["feed_refresh"] } }
    assert_response :success
    assert_not_nil css_select('[data-key="recent_events.%d"]' % refresh_event.id).first
    assert css_select('[data-key="recent_events.%d"]' % withdrawn_event.id).empty?
  end

  test "#show should carry the active filter into the polling endpoint" do
    sign_in_as user
    create(:feed, user: user)
    Event.create!(type: "feed_refresh", level: :info, message: "", user: user)

    get status_path, params: { filter: { type: ["feed_refresh"] } }
    assert_response :success
    assert_select "#recent_events_list[data-polling-endpoint-value*='feed_refresh']"
  end

  private

  def with_initial_events_limit(limit)
    original_limit = StatusesController.initial_events_limit
    StatusesController.initial_events_limit = limit
    yield
  ensure
    StatusesController.initial_events_limit = original_limit
  end
end
