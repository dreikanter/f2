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
    assert_select ".ff-stats__row", /Total feeds:\s+2/
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
    assert_select ".ff-stats__row", /Total imported posts:\s+2/
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
    assert_select ".ff-stats__row", /Total published posts:\s+2/
  end

  test "#show should display most recent post publication timestamp" do
    sign_in_as user
    feed = create(:feed, user: user)
    entry = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry, status: :published, published_at: 1.day.ago)

    get status_path
    assert_response :success
    assert_select ".ff-stats__row", /Most recent post publication:\s+1 day ago/
  end

  test "#show should hide most recent post publication when no published posts" do
    sign_in_as user

    get status_path
    assert_response :success
    assert_select ".ff-stats__row", { text: /Most recent post publication/, count: 0 }
  end

  test "#show should display average posts per day for last week" do
    sign_in_as user
    feed = create(:feed, user: user)
    entry1 = create(:feed_entry, feed: feed)
    entry2 = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry1, published_at: 2.days.ago)
    create(:post, feed: feed, feed_entry: entry2, published_at: 1.day.ago)

    get status_path
    assert_response :success
    assert_select ".ff-stats__row", /Average posts per day \(last week\):\s+0\.3/
  end

  test "#show should hide average posts per day when no posts" do
    sign_in_as user

    get status_path
    assert_response :success
    assert_select ".ff-stats__row", { text: /Average posts per day/, count: 0 }
  end

  test "#show should hide post statistics when no posts" do
    sign_in_as user

    get status_path
    assert_response :success
    assert_select ".ff-stats__row", { text: /Total imported posts/, count: 0 }
    assert_select ".ff-stats__row", { text: /Total published posts/, count: 0 }
    assert_select ".ff-stats__row", { text: /Most recent post publication/, count: 0 }
    assert_select ".ff-stats__row", { text: /Average posts per day/, count: 0 }
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
    assert_select ".ff-stats__row", /Total feeds:\s+1/
    assert_select "h1", "Status"
  end
end
