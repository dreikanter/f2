require "test_helper"

class FeedEntriesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user)
  end

  def other_feed
    @other_feed ||= create(:feed, user: other_user)
  end

  def feed_entry
    @feed_entry ||= create(:feed_entry, feed: feed)
  end

  def other_feed_entry
    @other_feed_entry ||= create(:feed_entry, feed: other_feed)
  end

  test "#show should redirect to login when not authenticated" do
    get feed_entry_url(feed_entry)
    assert_redirected_to new_session_path
  end

  test "#show should render for owned feed entry" do
    sign_in_as(user)
    get feed_entry_url(feed_entry)
    assert_response :success
    assert_select "h1", text: /Feed Entry \d+/
  end

  test "#show should reject access to other user's feed entry" do
    sign_in_as(user)
    get feed_entry_url(other_feed_entry)
    assert_response :not_found
  end

  test "#show should display status badge" do
    sign_in_as(user)
    pending_entry = create(:feed_entry, feed: feed, status: :pending)
    get feed_entry_url(pending_entry)
    assert_response :success
    assert_select "[data-key='feed_entry.status_badge']", text: "Pending"

    processed_entry = create(:feed_entry, feed: feed, status: :processed)
    get feed_entry_url(processed_entry)
    assert_response :success
    assert_select "[data-key='feed_entry.status_badge']", text: "Processed"
  end

  test "#show should display JSON data" do
    sign_in_as(user)
    get feed_entry_url(feed_entry)
    assert_response :success
    assert_select "pre", text: /#{feed_entry.uid}/
  end

  test "#show should display link to post when post exists" do
    sign_in_as(user)
    post = create(:post, feed: feed, feed_entry: feed_entry)
    get feed_entry_url(feed_entry)
    assert_response :success
    assert_select "a[href='#{post_path(post)}']", text: "Back to Post"
  end

  test "#show should display disabled link when no post exists" do
    sign_in_as(user)
    get feed_entry_url(feed_entry)
    assert_response :success
    assert_select "span.opacity-50", text: "Back to Post"
  end
end
