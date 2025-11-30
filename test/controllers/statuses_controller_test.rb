require "test_helper"

class StatusesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  test "#show should require authentication" do
    get status_path
    assert_redirected_to new_session_path
  end

  test "#show should render onboarding state 1 - no active tokens" do
    onboarding_user = create(:user, state: :onboarding)
    sign_in_as onboarding_user
    get status_path
    assert_response :success
    assert_select "h1", "Welcome to Feeder"
    assert_select "p", text: /add a FreeFeed access token/
    assert_select "a[href='#{new_access_token_path}']", text: "Add FreeFeed token"
  end

  test "#show should render onboarding state 2 - has token, no feeds" do
    onboarding_user = create(:user, state: :onboarding)
    create(:access_token, :active, user: onboarding_user)
    sign_in_as onboarding_user
    get status_path
    assert_response :success
    assert_select "h1", "Welcome to Feeder"
    assert_select "p", text: /create your first feed/
    assert_select "a[href='#{new_feed_path}']", text: "Add feed"
  end

  test "#show should render active state 3 - normal dashboard" do
    active_user = create(:user, state: :active)
    create(:access_token, :active, user: active_user)
    create(:feed, user: active_user)
    sign_in_as active_user
    get status_path
    assert_response :success
    assert_select "h1", "Status"
    assert_select "div.ff-alert", count: 0
  end

  test "#show should render active state 4 - missing active tokens warning" do
    active_user = create(:user, state: :active)
    inactive_token = create(:access_token, :inactive, user: active_user)
    create(:feed, user: active_user, access_token: inactive_token)
    sign_in_as active_user
    get status_path
    assert_response :success
    assert_select "h1", "Status"
    assert_select ".ff-alert--warning" do
      assert_select "p", text: /don't have any active FreeFeed tokens/
      assert_select "a[href='#{new_access_token_path}']", text: "Add a token"
    end
  end

  test "#show should display total feeds count" do
    active_user = create(:user, state: :active)
    create(:access_token, :active, user: active_user)
    sign_in_as active_user
    feed1 = create(:feed, user: active_user)
    feed2 = create(:feed, user: active_user)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="stats.total_feeds"]').first
    assert_equal "2", css_select('[data-key="stats.total_feeds.value"]').first.text.strip
  end

  test "#show should display total imported posts count" do
    active_user = create(:user, state: :active)
    create(:access_token, :active, user: active_user)
    sign_in_as active_user
    feed = create(:feed, user: active_user)
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
    active_user = create(:user, state: :active)
    create(:access_token, :active, user: active_user)
    sign_in_as active_user
    feed = create(:feed, user: active_user)
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
    active_user = create(:user, state: :active)
    create(:access_token, :active, user: active_user)
    sign_in_as active_user
    feed = create(:feed, user: active_user)
    entry = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry, status: :published, published_at: 1.day.ago)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="stats.most_recent_post_publication"]').first
    assert_match(/1 day ago/, css_select('[data-key="stats.most_recent_post_publication.value"]').first.text)
  end

  test "#show should hide most recent post publication when no published posts" do
    onboarding_user = create(:user, state: :onboarding)
    sign_in_as onboarding_user

    get status_path
    assert_response :success
    assert css_select('[data-key="stats.most_recent_post_publication"]').empty?
  end

  test "#show should display average posts per day for last week" do
    active_user = create(:user, state: :active)
    create(:access_token, :active, user: active_user)
    sign_in_as active_user
    feed = create(:feed, user: active_user)
    entry1 = create(:feed_entry, feed: feed)
    entry2 = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry1, published_at: 2.days.ago)
    create(:post, feed: feed, feed_entry: entry2, published_at: 1.day.ago)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="stats.average_posts_per_day"]').first
    assert_equal "0.3", css_select('[data-key="stats.average_posts_per_day.value"]').first.text.strip
  end

  test "#show should hide average posts per day when no posts" do
    onboarding_user = create(:user, state: :onboarding)
    sign_in_as onboarding_user

    get status_path
    assert_response :success
    assert css_select('[data-key="stats.average_posts_per_day"]').empty?
  end

  test "#show should hide post statistics when no posts" do
    onboarding_user = create(:user, state: :onboarding)
    sign_in_as onboarding_user

    get status_path
    assert_response :success
    assert css_select('[data-key="stats.total_imported_posts"]').empty?
    assert css_select('[data-key="stats.total_published_posts"]').empty?
    assert css_select('[data-key="stats.most_recent_post_publication"]').empty?
    assert css_select('[data-key="stats.average_posts_per_day"]').empty?
  end

  test "#show should render onboarding state when no feeds" do
    onboarding_user = create(:user, state: :onboarding)
    sign_in_as onboarding_user

    get status_path
    assert_response :success
    assert_select "h1", "Welcome to Feeder"
  end

  test "#show should display statistics when feeds exist and user is active" do
    active_user = create(:user, state: :active)
    create(:access_token, :active, user: active_user)
    sign_in_as active_user
    create(:feed, user: active_user)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="stats.total_feeds"]').first
    assert_equal "1", css_select('[data-key="stats.total_feeds.value"]').first.text.strip
    assert_select "h1", "Status"
  end

  test "#show should display recent user events" do
    active_user = create(:user, state: :active)
    create(:access_token, :active, user: active_user)
    sign_in_as active_user
    create(:feed, user: active_user)
    event1 = Event.create!(type: "feed_refresh", level: :info, message: "Feed refresh completed", user: active_user)
    event2 = Event.create!(type: "post_withdrawn", level: :info, message: "Post withdrawn", user: active_user)

    get status_path
    assert_response :success
    assert_select "h2", "Recent Activity"
    assert_not_nil css_select('[data-key="recent_events.%d"]' % event1.id).first
    assert_not_nil css_select('[data-key="recent_events.%d"]' % event2.id).first
  end

  test "#show should hide recent events section when no events" do
    active_user = create(:user, state: :active)
    create(:access_token, :active, user: active_user)
    sign_in_as active_user
    create(:feed, user: active_user)

    get status_path
    assert_response :success
    assert_select "h2", { text: "Recent Activity", count: 0 }
  end

  test "#show should only display user's own events" do
    active_user = create(:user, state: :active)
    create(:access_token, :active, user: active_user)
    other_user = create(:user)
    sign_in_as active_user
    create(:feed, user: active_user)
    user_event = Event.create!(type: "feed_refresh", level: :info, message: "User's event", user: active_user)
    other_event = Event.create!(type: "feed_refresh", level: :info, message: "Other's event", user: other_user)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="recent_events.%d"]' % user_event.id).first
    assert css_select('[data-key="recent_events.%d"]' % other_event.id).empty?
  end

  test "#show should exclude debug level events" do
    active_user = create(:user, state: :active)
    create(:access_token, :active, user: active_user)
    sign_in_as active_user
    create(:feed, user: active_user)
    info_event = Event.create!(type: "info_event", level: :info, message: "Info event", user: active_user)
    debug_event = Event.create!(type: "debug_event", level: :debug, message: "Debug event", user: active_user)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="recent_events.%d"]' % info_event.id).first
    assert css_select('[data-key="recent_events.%d"]' % debug_event.id).empty?
  end

  test "#show should exclude expired events" do
    active_user = create(:user, state: :active)
    create(:access_token, :active, user: active_user)
    sign_in_as active_user
    create(:feed, user: active_user)
    active_event = Event.create!(type: "active_event", level: :info, message: "Active event", user: active_user)
    expired_event = Event.create!(type: "expired_event", level: :info, message: "Expired event", user: active_user, expires_at: 1.hour.ago)

    get status_path
    assert_response :success
    assert_not_nil css_select('[data-key="recent_events.%d"]' % active_event.id).first
    assert css_select('[data-key="recent_events.%d"]' % expired_event.id).empty?
  end

  test "#show should limit to 10 recent events" do
    active_user = create(:user, state: :active)
    create(:access_token, :active, user: active_user)
    sign_in_as active_user
    create(:feed, user: active_user)
    15.times do |i|
      Event.create!(type: "event_#{i}", level: :info, message: "Event #{i}", user: active_user, created_at: i.minutes.ago)
    end

    get status_path
    assert_response :success
    events_in_page = css_select('[data-key^="recent_events."]:not([data-key$=".label"]):not([data-key$=".value"])')
    assert_equal 10, events_in_page.size
  end
end
