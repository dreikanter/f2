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
    total_item = css_select(".ff-list-group__item").find { |item| item.at_css(".ff-list-group__title")&.text&.strip == "Total feeds" }
    assert_not_nil total_item
    assert_equal "2", total_item.at_css(".ff-list-group__trailing-text").text.strip
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
    imported_item = css_select(".ff-list-group__item").find { |item| item.at_css(".ff-list-group__title")&.text&.strip == "Total imported posts" }
    assert_not_nil imported_item
    assert_equal "2", imported_item.at_css(".ff-list-group__trailing-text").text.strip
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
    published_item = css_select(".ff-list-group__item").find { |item| item.at_css(".ff-list-group__title")&.text&.strip == "Total published posts" }
    assert_not_nil published_item
    assert_equal "2", published_item.at_css(".ff-list-group__trailing-text").text.strip
  end

  test "#show should display most recent post publication timestamp" do
    sign_in_as user
    feed = create(:feed, user: user)
    entry = create(:feed_entry, feed: feed)
    create(:post, feed: feed, feed_entry: entry, status: :published, published_at: 1.day.ago)

    get status_path
    assert_response :success
    recent_item = css_select(".ff-list-group__item").find { |item| item.at_css(".ff-list-group__title")&.text&.strip == "Most recent post publication" }
    assert_not_nil recent_item
    assert_match(/1 day ago/, recent_item.at_css(".ff-list-group__trailing-text").text)
  end

  test "#show should hide most recent post publication when no published posts" do
    sign_in_as user

    get status_path
    assert_response :success
    refute_includes stats_titles, "Most recent post publication"
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
    average_item = css_select(".ff-list-group__item").find { |item| item.at_css(".ff-list-group__title")&.text&.strip == "Average posts per day (last week)" }
    assert_not_nil average_item
    assert_equal "0.3", average_item.at_css(".ff-list-group__trailing-text").text.strip
  end

  test "#show should hide average posts per day when no posts" do
    sign_in_as user

    get status_path
    assert_response :success
    refute_includes stats_titles, "Average posts per day (last week)"
  end

  test "#show should hide post statistics when no posts" do
    sign_in_as user

    get status_path
    assert_response :success
    titles = stats_titles
    refute_includes titles, "Total imported posts"
    refute_includes titles, "Total published posts"
    refute_includes titles, "Most recent post publication"
    refute_includes titles, "Average posts per day (last week)"
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
    total_item = css_select(".ff-list-group__item").find { |item| item.at_css(".ff-list-group__title")&.text&.strip == "Total feeds" }
    assert_not_nil total_item
    assert_equal "1", total_item.at_css(".ff-list-group__trailing-text").text.strip
    assert_select "h1", "Status"
  end

  private

  def stats_titles
    css_select(".ff-list-group__item .ff-list-group__title").map { |node| node.text.strip }
  end
end
