require "test_helper"

class Admin::FeedsControllerTest < ActionDispatch::IntegrationTest
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

  test "should redirect non-admin users from index" do
    sign_in_as(regular_user)

    get admin_feeds_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "should redirect unauthenticated users from index" do
    get admin_feeds_path

    assert_redirected_to new_session_path
  end

  test "should list feeds from every user for admins" do
    sign_in_as(admin_user)
    feed = create(:feed, user: create(:user))

    get admin_feeds_path

    assert_response :success
    assert_select "h1", "Feeds"
    assert_select "a[href=?]", admin_feed_path(feed), text: feed.display_name
  end

  test "should let admins view another user's feed" do
    sign_in_as(admin_user)
    feed = create(:feed, user: create(:user))

    get admin_feed_path(feed)

    assert_response :success
    assert_select "h1", feed.display_name
  end

  test "should show another user's feed posts without owner-only links" do
    sign_in_as(admin_user)
    feed = create(:feed, user: create(:user))
    post = create(:post, :published, feed: feed)

    get admin_feed_path(feed)

    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(post)}"
    assert_select "a[href=?]", post_path(post), count: 0
  end

  test "#show should render a recent activity section with the feed's events" do
    sign_in_as(admin_user)
    feed = create(:feed, user: create(:user))
    create(:event, subject: feed, user: feed.user)

    get admin_feed_path(feed)

    assert_response :success
    assert_select "h2", text: "Recent Activity", count: 1
  end

  test "#show should not render recent activity section when feed has no events" do
    sign_in_as(admin_user)
    feed = create(:feed, user: create(:user))

    get admin_feed_path(feed)

    assert_response :success
    assert_select "h2", text: "Recent Activity", count: 0
  end

  test "#show should render a recent posts section with the feed's posts" do
    sign_in_as(admin_user)
    feed = create(:feed, user: create(:user))
    create(:post, feed: feed)

    get admin_feed_path(feed)

    assert_response :success
    assert_select "h2", text: "Recent Posts", count: 1
  end

  test "#show should not render recent posts section when feed has no posts" do
    sign_in_as(admin_user)
    feed = create(:feed, user: create(:user))

    get admin_feed_path(feed)

    assert_response :success
    assert_select "h2", text: "Recent Posts", count: 0
  end

  test "#show should render AI usage section when feed has usages within the stats period" do
    sign_in_as(admin_user)
    feed = create(:feed, user: create(:user))
    create(:llm_usage, feed: feed, user: feed.user)

    get admin_feed_path(feed)

    assert_response :success
    assert_select "h2", text: "AI Usage", count: 1
  end

  test "#show should not render AI usage section when all usages are older than the stats period" do
    sign_in_as(admin_user)
    feed = create(:feed, user: create(:user))
    create(:llm_usage, feed: feed, user: feed.user, created_at: LlmUsage::STATS_PERIOD.ago - 1.day)

    get admin_feed_path(feed)

    assert_response :success
    assert_select "h2", text: "AI Usage", count: 0
  end

  test "should redirect non-admin users from show" do
    sign_in_as(regular_user)
    feed = create(:feed, user: create(:user))

    get admin_feed_path(feed)

    assert_redirected_to root_path
  end

  test "should render the sort dropdown on index" do
    sign_in_as(admin_user)
    create(:feed, user: create(:user))

    get admin_feeds_path

    assert_response :success
    assert_select "button[data-dropdown-toggle='admin-feed-sort-menu']", 1
    assert_select "#admin-feed-sort-menu a", Admin::FeedsController::SORTABLE_FIELDS.size
  end

  test "should sort feeds by name" do
    sign_in_as(admin_user)
    create(:feed, user: create(:user), name: "Z Feed")
    create(:feed, user: create(:user), name: "A Feed")

    get admin_feeds_path(sort: "name", direction: "asc")

    assert_response :success
    assert response.body.index("A Feed") < response.body.index("Z Feed"),
      "Expected A Feed to appear before Z Feed"
  end

  test "should preserve sort parameters in pagination" do
    sign_in_as(admin_user)
    3.times { |i| create(:feed, user: create(:user), name: "Feed #{i}") }

    get admin_feeds_path(sort: "name", direction: "desc", per_page: 2)

    assert_response :success
    assert_select "nav a[href*='sort=name']"
    assert_select "nav a[href*='direction=desc']"
  end
end
