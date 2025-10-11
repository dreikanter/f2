require "test_helper"

class StatusesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  test "requires authentication" do
    get status_path
    assert_redirected_to new_session_path
  end

  test "shows status when authenticated with no feeds" do
    sign_in_as user
    get status_path
    assert_response :success
    assert_select "h1", "Welcome to Feeder"
  end

  test "shows status when authenticated with feeds" do
    sign_in_as user
    create(:feed, user: user)
    get status_path
    assert_response :success
    assert_select "h1", "Status"
  end

  test "displays total feeds count" do
    sign_in_as user
    feed1 = create(:feed, user: user)
    feed2 = create(:feed, user: user)

    get status_path
    assert_response :success
    assert_select ".list-group-item", /Total feeds:\s+2/
  end

  test "displays total imported posts count" do
    sign_in_as user
    feed = create(:feed, user: user)
    entry1 = create(:feed_entry, feed: feed)
    entry2 = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry1)
    create(:post, feed: feed, feed_entry: entry2)

    get status_path
    assert_response :success
    assert_select ".list-group-item", /Total imported posts:\s+2/
  end

  test "displays total published posts count" do
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
    assert_select ".list-group-item", /Total published posts:\s+2/
  end

  test "displays most recent post publication timestamp" do
    sign_in_as user
    feed = create(:feed, user: user)
    entry = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry, status: :published, published_at: 1.day.ago)

    get status_path
    assert_response :success
    assert_select ".list-group-item", /Most recent post publication:\s+1 day ago/
  end

  test "hides most recent post publication when no published posts" do
    sign_in_as user

    get status_path
    assert_response :success
    assert_select ".list-group-item", { text: /Most recent post publication/, count: 0 }
  end

  test "displays average posts per day for last week" do
    sign_in_as user
    feed = create(:feed, user: user)
    entry1 = create(:feed_entry, feed: feed)
    entry2 = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry1, published_at: 2.days.ago)
    create(:post, feed: feed, feed_entry: entry2, published_at: 1.day.ago)

    get status_path
    assert_response :success
    assert_select ".list-group-item", /Average posts per day \(last week\):\s+0\.3/
  end

  test "hides average posts per day when no posts" do
    sign_in_as user

    get status_path
    assert_response :success
    assert_select ".list-group-item", { text: /Average posts per day/, count: 0 }
  end

  test "hides post statistics when no posts" do
    sign_in_as user

    get status_path
    assert_response :success
    assert_select ".list-group-item", { text: /Total imported posts/, count: 0 }
    assert_select ".list-group-item", { text: /Total published posts/, count: 0 }
    assert_select ".list-group-item", { text: /Most recent post publication/, count: 0 }
    assert_select ".list-group-item", { text: /Average posts per day/, count: 0 }
  end

  test "displays empty state when no feeds" do
    sign_in_as user

    get status_path
    assert_response :success
    assert_select "h1", "Welcome to Feeder"
    assert_select "p", /This page shows statistics about your feeds and posts/
    assert_select "a[href=?]", new_feed_path, text: "Add your first feed"
    assert_select ".list-group", count: 0
  end

  test "displays statistics when feeds exist" do
    sign_in_as user
    create(:feed, user: user)

    get status_path
    assert_response :success
    assert_select ".list-group-item", /Total feeds:\s+1/
    assert_select "h1", "Status"
  end
end
