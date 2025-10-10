require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
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

  def user_post
    @user_post ||= create(:post, :published, feed: feed)
  end

  def other_user_post
    @other_user_post ||= create(:post, feed: other_feed)
  end

  test "should redirect to login when not authenticated" do
    get posts_url
    assert_redirected_to new_session_path
  end

  test "should get index when authenticated" do
    sign_in_as(user)
    get posts_url
    assert_response :success
    assert_select "h1", "Posts"
  end

  test "should show only user's posts in index" do
    sign_in_as(user)
    create(:post, feed: feed, content: "User's post")
    create(:post, feed: other_feed, content: "Other user's post")

    get posts_url
    assert_response :success
    assert_select "td", text: /User's post/
    assert_select "td", { text: /Other user's post/, count: 0 }
  end

  test "should paginate posts in index" do
    sign_in_as(user)
    26.times { |i| create(:post, feed: feed, content: "Post #{i}") }

    get posts_url
    assert_response :success
    assert_select ".pagination"
  end

  test "should redirect to login when accessing show without authentication" do
    get post_url(user_post)
    assert_redirected_to new_session_path
  end

  test "should get show when authenticated and owns post" do
    sign_in_as(user)
    get post_url(user_post)
    assert_response :success
    assert_select "h1", "Post Details"
  end

  test "should not allow access to other user's post" do
    sign_in_as(user)
    # Create a post that belongs to another user's feed in a clean way
    other_user = create(:user)
    other_feed_local = create(:feed, user: other_user)
    other_post_local = create(:post, feed: other_feed_local)

    get post_url(other_post_local)
    assert_response :not_found
  end

  test "should display post content and metadata in show" do
    sign_in_as(user)
    post_with_data = create(:post, :published, :with_attachments, :with_comments,
                           feed: feed,
                           content: "Test post content",
                           published_at: Time.current)

    get post_url(post_with_data)
    assert_response :success
    assert_select "div", text: /Test post content/
    assert_select "strong", text: "Status:"
    assert_select "strong", text: "Attachments (2):"
    assert_select "strong", text: "Comments (1):"
  end

  test "should display validation errors when present" do
    sign_in_as(user)
    post_with_errors = create(:post, :rejected, feed: feed)

    get post_url(post_with_errors)
    assert_response :success
    assert_select ".alert-danger"
  end

  test "should show correct status" do
    sign_in_as(user)

    enqueued_post = create(:post, :enqueued, feed: feed)
    get post_url(enqueued_post)
    assert_select "strong", text: "Status:"

    failed_post = create(:post, :failed, feed: feed)
    get post_url(failed_post)
    assert_select "strong", text: "Status:"

    rejected_post = create(:post, :rejected, feed: feed)
    get post_url(rejected_post)
    assert_select "strong", text: "Status:"
  end

  test "should display external links when available" do
    sign_in_as(user)
    published_post = create(:post, :published, feed: feed, freefeed_post_id: "test-123")
    feed.update(target_group: "testgroup")

    get post_url(published_post)
    assert_response :success
    assert_select "a[href*='#{feed.access_token.host}/testgroup/test-123']", text: "View on FreeFeed"
    assert_select "a[href='#{published_post.source_url}']", text: "View Original Source"
  end

  test "destroy withdraws post and creates event" do
    sign_in_as(user)
    published_post = create(:post, :published, feed: feed, freefeed_post_id: "test-123")

    assert_enqueued_with(job: PostWithdrawalJob) do
      assert_difference("Event.count", 1) do
        delete post_url(published_post), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
    assert_includes response.body, "turbo-stream"
    assert_includes response.body, dom_id(published_post)
    assert_includes response.body, "The post will be withdrawn from FreeFeed"
    assert_equal "withdrawn", published_post.reload.status

    event = Event.last
    assert_equal "PostWithdrawn", event.type
    assert_equal user, event.user
    assert_equal published_post, event.subject
    assert_equal "info", event.level
  end

  test "destroy requires authentication" do
    published_post = create(:post, :published, feed: feed)

    delete post_url(published_post)
    assert_redirected_to new_session_path
  end

  test "destroy requires ownership" do
    sign_in_as(user)
    other_user = create(:user)
    other_feed = create(:feed, user: other_user)
    other_post = create(:post, :published, feed: other_feed)

    delete post_url(other_post)
    assert_response :not_found
  end

  test "destroy requires published status" do
    sign_in_as(user)
    draft_post = create(:post, :draft, feed: feed)

    delete post_url(draft_post)
    assert_redirected_to root_path
  end
end
