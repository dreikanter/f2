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
    login_as(regular_user)

    get admin_feeds_path

    assert_redirected_to root_path
    assert_equal "Access denied. You don't have permission to perform this action.", flash[:alert]
  end

  test "should redirect unauthenticated users from index" do
    get admin_feeds_path

    assert_redirected_to new_session_path
  end

  test "should list feeds from every user for admins" do
    login_as(admin_user)
    feed = create(:feed, user: create(:user))

    get admin_feeds_path

    assert_response :success
    assert_select "h1", "Feeds"
    assert_select "a[href=?]", admin_feed_path(feed), text: feed.display_name
  end

  test "should let admins view another user's feed" do
    login_as(admin_user)
    feed = create(:feed, user: create(:user))

    get admin_feed_path(feed)

    assert_response :success
    assert_select "h1", feed.display_name
  end

  test "should show another user's feed posts without owner-only links" do
    login_as(admin_user)
    feed = create(:feed, user: create(:user))
    post = create(:post, :published, feed: feed)

    get admin_feed_path(feed)

    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(post)}"
    assert_select "a[href=?]", post_path(post), count: 0
  end

  test "should redirect non-admin users from show" do
    login_as(regular_user)
    feed = create(:feed, user: create(:user))

    get admin_feed_path(feed)

    assert_redirected_to root_path
  end

  def login_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end
end
