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

  test "#index should redirect to login when not authenticated" do
    get posts_url
    assert_redirected_to new_session_path
  end

  test "#index should render when authenticated" do
    sign_in_as(user)
    get posts_url
    assert_response :success
    assert_select "h1", "Posts"
  end

  test "#index should nudge users with no feeds toward adding one" do
    sign_in_as(user)
    get posts_url
    assert_response :success
    assert_select "[data-key='empty-state'] a[href=?]", new_feed_path, text: "Add your first feed"
  end

  test "#index should explain the empty state when feeds exist but no posts" do
    sign_in_as(user)
    feed
    get posts_url
    assert_response :success
    assert_select "[data-key='empty-state']", text: /No posts yet/
    assert_select "[data-key='empty-state'] a", false
  end

  test "#index should show only user's posts" do
    sign_in_as(user)
    create(:post, feed: feed, content: "User's post")
    create(:post, feed: other_feed, content: "Other user's post")

    get posts_url
    assert_response :success
    assert_select "a[href*='/posts/']", text: /User's post/
    assert_no_match(/Other user&#39;s post/, response.body)
  end

  test "#index should paginate posts" do
    sign_in_as(user)
    4.times { |i| create(:post, feed: feed, content: "Post #{i}") }

    get posts_url, params: { per_page: 3 }
    assert_response :success
    assert_select "nav[aria-label='Posts pagination']"
  end

  test "#show should redirect to login when not authenticated" do
    get post_url(user_post)
    assert_redirected_to new_session_path
  end

  test "#show should render for owned post" do
    sign_in_as(user)
    get post_url(user_post)
    assert_response :success
    assert_select "h1", text: /Post \d+/
  end

  test "#show should reject access to other user's post" do
    sign_in_as(user)
    # Create a post that belongs to another user's feed in a clean way
    other_user = create(:user)
    other_feed_local = create(:feed, user: other_user)
    other_post_local = create(:post, feed: other_feed_local)

    get post_url(other_post_local)
    assert_response :not_found
  end

  test "#show should display post content and metadata" do
    sign_in_as(user)
    post_with_data = create(:post, :published, :with_attachments, :with_comments,
                           feed: feed,
                           content: "Test post content",
                           published_at: Time.current)

    get post_url(post_with_data)
    assert_response :success
    assert_select "div", text: /Test post content/
    assert_select "[data-key='post.status_badge']", text: "Published"
    assert_select "[data-key='post.attachments']"
    assert_select "[data-key='post.comments']"
  end

  test "#show should include accessible labels for attachment thumbnails" do
    sign_in_as(user)
    post_with_attachments = create(:post, :published, :with_attachments, feed: feed)

    get post_url(post_with_attachments)
    assert_response :success
    assert_select "[data-key='post.attachments'] a[href*='image1.jpg'] img[alt='image1.jpg']"
    assert_select "[data-key='post.attachments'] a[href*='image2.png'] img[alt='image2.png']"
  end

  test "#show should display validation errors when present" do
    sign_in_as(user)
    post_with_errors = create(:post, :rejected, feed: feed)

    get post_url(post_with_errors)
    assert_response :success
    assert_select "[data-key='post.validation_errors']"
  end

  test "#show should display correct status" do
    sign_in_as(user)

    enqueued_post = create(:post, :enqueued, feed: feed)
    get post_url(enqueued_post)
    assert_select "[data-key='post.status_badge']", text: "Enqueued"

    failed_post = create(:post, :failed, feed: feed)
    get post_url(failed_post)
    assert_select "[data-key='post.status_badge']", text: "Failed"

    rejected_post = create(:post, :rejected, feed: feed)
    get post_url(rejected_post)
    assert_select "[data-key='post.status_badge']", text: "Rejected"
  end

  test "#show should display external links when available" do
    sign_in_as(user)
    published_post = create(:post, :published, feed: feed, freefeed_post_id: "test-123")
    feed.update(target_group: "testgroup")

    get post_url(published_post)
    assert_response :success
    assert_select "[data-key='post.source_url']"
    assert_select "a[href='#{published_post.source_url}']"
    assert_select "[data-key='post.freefeed_post_id']"
  end

  test "#show should gather post actions in the header menu" do
    sign_in_as(user)
    published_post = create(:post, :published, feed: feed)

    get post_url(published_post)

    assert_response :success
    assert_select "button[data-dropdown-toggle='post-header-menu-#{published_post.id}']"
    assert_select "#post-header-menu-#{published_post.id} a[data-key='post.source'][href='#{feed_entry_path(published_post.feed_entry)}']", text: "Source"
    assert_select "#post-header-menu-#{published_post.id} a[data-key='post.delete']", text: "Delete…"
  end

  test "#show should omit delete from the menu when deletion is not allowed" do
    sign_in_as(user)
    draft_post = create(:post, feed: feed)

    get post_url(draft_post)

    assert_response :success
    assert_select "#post-header-menu-#{draft_post.id} a[data-key='post.source']", text: "Source"
    assert_select "#post-header-menu-#{draft_post.id} a[data-key='post.delete']", count: 0
  end

  test "#destroy should withdraw the FreeFeed post and create event" do
    sign_in_as(user)
    published_post = create(:post, :published, feed: feed, freefeed_post_id: "test-123")

    assert_enqueued_with(job: PostWithdrawalJob, args: [feed.id, "test-123", published_post.id]) do
      assert_difference("Event.count", 1) do
        delete post_url(published_post), params: { delete_freefeed_post: "1" },
                                         headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
    assert_includes response.body, "turbo-stream"
    assert_includes response.body, "id=\"#{dom_id(published_post)}\""
    assert_includes response.body, "Withdrawn"
    assert_includes response.body, "The post will be withdrawn from FreeFeed"
    assert_equal "withdrawn", published_post.reload.status

    event = Event.last
    assert_equal "post_withdrawn", event.type
    assert_equal user, event.user
    assert_equal published_post, event.subject
    assert_equal "info", event.level
  end

  test "#destroy should refresh the daily published metric after withdrawing" do
    sign_in_as(user)
    create(:post, :published, feed: feed, reposted_at: Time.current)
    withdrawing = create(:post, :published, feed: feed, freefeed_post_id: "test-123", reposted_at: Time.current)

    delete post_url(withdrawing), params: { delete_freefeed_post: "1" }

    metric = FeedMetric.find_by(feed: feed, date: Date.current)
    assert_equal 1, metric.published_posts_count
  end

  test "#destroy should refresh the daily published metric after deleting the record" do
    sign_in_as(user)
    create(:post, :published, feed: feed, reposted_at: Time.current)
    feed_entry = create(:feed_entry, feed: feed, uid: "entry-1")
    deleting = create(:post, :published, feed: feed, feed_entry: feed_entry,
      uid: "entry-1", freefeed_post_id: "test-123", reposted_at: Time.current)

    delete post_url(deleting), params: { delete_freefeed_post: "1", delete_record: "1" }

    metric = FeedMetric.find_by(feed: feed, date: Date.current)
    assert_equal 1, metric.published_posts_count
  end

  test "#destroy should reload the post page after withdrawing it" do
    sign_in_as(user)
    published_post = create(:post, :published, feed: feed, freefeed_post_id: "test-123")

    delete post_url(published_post), params: { delete_freefeed_post: "1" }

    assert_redirected_to post_path(published_post)
    assert_equal "withdrawn", published_post.reload.status
  end

  test "#destroy should redirect to the index after deleting the record" do
    sign_in_as(user)
    published_post = create(:post, :published, feed: feed, freefeed_post_id: "test-123")

    delete post_url(published_post), params: { delete_freefeed_post: "1", delete_record: "1" }

    assert_redirected_to posts_path
    assert_nil Post.find_by(id: published_post.id)
  end

  test "#destroy should delete the post record and let it be imported again" do
    sign_in_as(user)
    feed_entry = create(:feed_entry, feed: feed, uid: "entry-1")
    create(:feed_entry_uid, feed: feed, uid: "entry-1")
    published_post = create(:post, :published, feed: feed, feed_entry: feed_entry,
      uid: "entry-1", freefeed_post_id: "test-123")

    assert_difference(["Post.count", "FeedEntry.count", "FeedEntryUid.count"], -1) do
      assert_difference("Event.count", 1) do
        delete post_url(published_post), params: { delete_freefeed_post: "1", delete_record: "1" },
                                         headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
    assert_includes response.body, "turbo-stream"
    assert_includes response.body, "remove"
    assert_nil Post.find_by(id: published_post.id)
    assert_empty FeedEntryUid.where(feed: feed, uid: "entry-1")

    event = Event.last
    assert_equal "post_deleted", event.type
    assert_equal feed, event.subject
  end

  test "#destroy should not drop the FreeFeed post when only the record is deleted" do
    sign_in_as(user)
    published_post = create(:post, :published, feed: feed, freefeed_post_id: "test-123")

    assert_no_enqueued_jobs(only: PostWithdrawalJob) do
      delete post_url(published_post), params: { delete_record: "1" },
                                       headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_nil Post.find_by(id: published_post.id)
  end

  test "#destroy should let a withdrawn post's record be deleted" do
    sign_in_as(user)
    feed_entry = create(:feed_entry, feed: feed, uid: "entry-9")
    create(:feed_entry_uid, feed: feed, uid: "entry-9")
    withdrawn_post = create(:post, feed: feed, feed_entry: feed_entry, uid: "entry-9", status: :withdrawn)

    assert_difference(["Post.count", "FeedEntryUid.count"], -1) do
      delete post_url(withdrawn_post), params: { delete_record: "1" },
                                       headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_nil Post.find_by(id: withdrawn_post.id)
  end

  test "#destroy should let a failed post's record be deleted" do
    sign_in_as(user)
    feed_entry = create(:feed_entry, feed: feed, uid: "entry-fail")
    create(:feed_entry_uid, feed: feed, uid: "entry-fail")
    failed_post = create(:post, :failed, feed: feed, feed_entry: feed_entry, uid: "entry-fail")

    assert_no_enqueued_jobs(only: PostWithdrawalJob) do
      assert_difference(["Post.count", "FeedEntryUid.count"], -1) do
        delete post_url(failed_post), params: { delete_record: "1" },
                                      headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
    assert_nil Post.find_by(id: failed_post.id)
  end

  test "#destroy should do nothing when no option is selected" do
    sign_in_as(user)
    published_post = create(:post, :published, feed: feed, freefeed_post_id: "test-123")

    assert_no_enqueued_jobs(only: PostWithdrawalJob) do
      assert_no_difference(["Post.count", "Event.count"]) do
        delete post_url(published_post)
      end
    end

    assert_redirected_to posts_path
    assert_equal "published", published_post.reload.status
  end

  test "#destroy should require authentication" do
    published_post = create(:post, :published, feed: feed)

    delete post_url(published_post)
    assert_redirected_to new_session_path
  end

  test "#destroy should require ownership" do
    sign_in_as(user)
    other_user = create(:user)
    other_feed = create(:feed, user: other_user)
    other_post = create(:post, :published, feed: other_feed)

    delete post_url(other_post)
    assert_response :not_found
  end

  test "#destroy should require published status" do
    sign_in_as(user)
    draft_post = create(:post, :draft, feed: feed)

    delete post_url(draft_post)
    assert_redirected_to root_path
  end

  test "#index should show feed filter dropdown with user's feeds" do
    sign_in_as(user)
    create(:feed, user: user, name: "Alpha Feed")
    create(:feed, user: other_user, name: "Other User Feed")

    get posts_url
    assert_response :success
    assert_select "[data-key='feed-filter.dropdown']"
    assert_select "[data-key='feed-filter.dropdown']", text: /All feeds/
    assert_select "[data-key='feed-filter.dropdown']", text: /Alpha Feed/
    assert_no_match(/Other User Feed/, response.body)
  end

  test "#index should filter posts by feed_id param" do
    sign_in_as(user)
    feed_a = create(:feed, user: user, name: "Feed A")
    feed_b = create(:feed, user: user, name: "Feed B")
    create(:post, feed: feed_a, content: "From feed A")
    create(:post, feed: feed_b, content: "From feed B")

    get posts_url(feed_id: feed_a.id)
    assert_response :success
    assert_match(/From feed A/, response.body)
    assert_no_match(/From feed B/, response.body)
  end

  test "#index should show selected feed name in filter button" do
    sign_in_as(user)
    filtered_feed = create(:feed, user: user, name: "Filtered Feed")
    create(:post, feed: filtered_feed)

    get posts_url(feed_id: filtered_feed.id)
    assert_response :success
    assert_select "[data-key='feed-filter.button']", text: /Filtered Feed/
  end

  test "#index should sort posts by feed name ascending" do
    sign_in_as(user)
    feed_a = create(:feed, user: user, name: "A Feed")
    feed_z = create(:feed, user: user, name: "Z Feed")
    create(:post, feed: feed_z, content: "Post Z")
    create(:post, feed: feed_a, content: "Post A")

    get posts_url(sort: "feed", direction: "asc")
    assert_response :success

    response_body = response.body
    pos_a = response_body.index("Post A")
    pos_z = response_body.index("Post Z")
    assert pos_a < pos_z, "Expected Post A to appear before Post Z"
  end

  test "#index should sort posts by feed name descending" do
    sign_in_as(user)
    feed_a = create(:feed, user: user, name: "A Feed")
    feed_z = create(:feed, user: user, name: "Z Feed")
    create(:post, feed: feed_z, content: "Post Z")
    create(:post, feed: feed_a, content: "Post A")

    get posts_url(sort: "feed", direction: "desc")
    assert_response :success

    response_body = response.body
    pos_a = response_body.index("Post A")
    pos_z = response_body.index("Post Z")
    assert pos_z < pos_a, "Expected Post Z to appear before Post A"
  end

  test "#index should sort posts by published date ascending" do
    sign_in_as(user)
    old_post = create(:post, feed: feed, content: "Old post", published_at: 2.days.ago)
    new_post = create(:post, feed: feed, content: "New post", published_at: 1.day.ago)

    get posts_url(sort: "published", direction: "asc")
    assert_response :success

    response_body = response.body
    pos_old = response_body.index("Old post")
    pos_new = response_body.index("New post")
    assert pos_old < pos_new, "Expected old post to appear before new post"
  end

  test "#index should sort posts by published date descending" do
    sign_in_as(user)
    old_post = create(:post, feed: feed, content: "Old post", published_at: 2.days.ago)
    new_post = create(:post, feed: feed, content: "New post", published_at: 1.day.ago)

    get posts_url(sort: "published", direction: "desc")
    assert_response :success

    response_body = response.body
    pos_old = response_body.index("Old post")
    pos_new = response_body.index("New post")
    assert pos_new < pos_old, "Expected new post to appear before old post"
  end

  test "#index should sort posts by status" do
    sign_in_as(user)
    draft_post = create(:post, :draft, feed: feed, content: "Draft post")
    published_post = create(:post, :published, feed: feed, content: "Published post")

    get posts_url(sort: "status", direction: "asc")
    assert_response :success

    response_body = response.body
    pos_draft = response_body.index("Draft post")
    pos_published = response_body.index("Published post")
    assert pos_draft < pos_published, "Expected draft post to appear before published post"
  end

  test "#index should sort posts by attachments count" do
    sign_in_as(user)
    post_with_attachments = create(:post, :with_attachments, feed: feed, content: "Post with attachments")
    post_without_attachments = create(:post, feed: feed, content: "Post without attachments")

    get posts_url(sort: "attachments", direction: "desc")
    assert_response :success

    response_body = response.body
    pos_with = response_body.index("Post with attachments")
    pos_without = response_body.index("Post without attachments")
    assert pos_with < pos_without, "Expected post with attachments to appear first"
  end

  test "#index should sort posts by comments count" do
    sign_in_as(user)
    post_with_comments = create(:post, :with_comments, feed: feed, content: "Post with comments")
    post_without_comments = create(:post, feed: feed, content: "Post without comments")

    get posts_url(sort: "comments", direction: "desc")
    assert_response :success

    response_body = response.body
    pos_with = response_body.index("Post with comments")
    pos_without = response_body.index("Post without comments")
    assert pos_with < pos_without, "Expected post with comments to appear first"
  end

  test "#index should sort posts by reposted date ascending" do
    sign_in_as(user)
    old_post = create(:post, :published, feed: feed, content: "Old post", reposted_at: 2.days.ago)
    new_post = create(:post, :published, feed: feed, content: "New post", reposted_at: 1.day.ago)

    get posts_url(sort: "reposted", direction: "asc")
    assert_response :success

    response_body = response.body
    pos_old = response_body.index("Old post")
    pos_new = response_body.index("New post")
    assert pos_old < pos_new, "Expected old post to appear before new post"
  end

  test "#index should sort posts by reposted date descending" do
    sign_in_as(user)
    old_post = create(:post, :published, feed: feed, content: "Old post", reposted_at: 2.days.ago)
    new_post = create(:post, :published, feed: feed, content: "New post", reposted_at: 1.day.ago)

    get posts_url(sort: "reposted", direction: "desc")
    assert_response :success

    response_body = response.body
    pos_old = response_body.index("Old post")
    pos_new = response_body.index("New post")
    assert pos_new < pos_old, "Expected new post to appear before old post"
  end

  test "#index should sort unreposted posts last when sorting by reposted date" do
    sign_in_as(user)
    reposted_post = create(:post, :published, feed: feed, content: "Reposted post", reposted_at: 1.day.ago)
    draft_post = create(:post, feed: feed, content: "Draft post", reposted_at: nil)

    get posts_url(sort: "reposted", direction: "desc")
    assert_response :success

    response_body = response.body
    pos_reposted = response_body.index("Reposted post")
    pos_draft = response_body.index("Draft post")
    assert pos_reposted < pos_draft, "Expected reposted post to appear before the one without a repost date"
  end

  test "#index should default to sorting by reposted date when no sort parameter provided" do
    sign_in_as(user)
    old_post = create(:post, :published, feed: feed, content: "Old post", reposted_at: 2.days.ago)
    new_post = create(:post, :published, feed: feed, content: "New post", reposted_at: 1.day.ago)

    get posts_url
    assert_response :success

    response_body = response.body
    pos_old = response_body.index("Old post")
    pos_new = response_body.index("New post")
    assert pos_new < pos_old, "Expected new post to appear before old post (default sort)"
  end

  test "#pagination should preserve sort parameters" do
    sign_in_as(user)
    3.times { |i| create(:post, feed: feed, content: "Post #{i}") }

    get posts_url(sort: "feed", direction: "asc", per_page: 2)
    assert_response :success
    assert_select "nav[aria-label='Posts pagination'] a[href*='sort=feed']"
    assert_select "nav[aria-label='Posts pagination'] a[href*='direction=asc']"
  end
end
