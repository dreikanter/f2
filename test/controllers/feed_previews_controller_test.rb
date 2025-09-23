require "test_helper"

class FeedPreviewsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def feed_profile
    @feed_profile ||= create(:feed_profile, user: user)
  end

  def feed
    @feed ||= create(:feed, user: user, feed_profile: feed_profile)
  end

  def feed_preview
    @feed_preview ||= create(:feed_preview, feed_profile: feed_profile, user: user)
  end

  test "should redirect to login when not authenticated" do
    post feed_previews_url, params: { url: "https://example.com/feed.xml", feed_profile_name: feed_profile.name }
    assert_redirected_to new_session_path
  end

  test "should create preview with feed_profile_name" do
    sign_in_as(user)

    assert_difference("FeedPreview.count", 1) do
      post feed_previews_url, params: {
        url: "https://example.com/feed.xml",
        feed_profile_name: feed_profile.name
      }
    end

    preview = FeedPreview.last
    assert_equal "https://example.com/feed.xml", preview.url
    assert_equal feed_profile, preview.feed_profile
    assert_equal user, preview.user
    assert_redirected_to feed_preview_path(preview)
  end

  test "should create preview with feed profile name" do
    sign_in_as(user)

    assert_difference("FeedPreview.count", 1) do
      post feed_previews_url, params: {
        url: "https://example.com/feed.xml",
        feed_profile_name: feed_profile.name
      }
    end

    preview = FeedPreview.last
    assert_equal "https://example.com/feed.xml", preview.url
    assert_equal feed_profile, preview.feed_profile
    assert_redirected_to feed_preview_path(preview)
  end

  test "should reuse existing feed profile with same name" do
    sign_in_as(user)

    # Create first preview
    post feed_previews_url, params: {
      url: "https://example.com/feed1.xml",
      feed_profile_name: feed_profile.name
    }

    assert_difference("FeedPreview.count", 1) do
      assert_no_difference("FeedProfile.count") do
        post feed_previews_url, params: {
          url: "https://example.com/feed2.xml",
          feed_profile_name: feed_profile.name
        }
      end
    end

    # Both previews should use the same feed profile
    previews = FeedPreview.last(2)
    assert_equal previews[0].feed_profile, previews[1].feed_profile
  end

  test "should not create preview with invalid URL" do
    sign_in_as(user)

    assert_no_difference("FeedPreview.count") do
      post feed_previews_url, params: {
        url: "invalid-url",
        feed_profile_id: feed_profile.id
      }
    end

    assert_redirected_to feeds_path
    follow_redirect!
    assert_includes response.body, "Invalid URL provided"
  end

  test "should not create preview without feed configuration" do
    sign_in_as(user)

    assert_no_difference("FeedPreview.count") do
      post feed_previews_url, params: {
        url: "https://example.com/feed.xml"
      }
    end

    assert_redirected_to feeds_path
    follow_redirect!
    assert_includes response.body, "Invalid feed configuration"
  end

  test "should show preview" do
    sign_in_as(user)
    get feed_preview_url(feed_preview)
    assert_response :success
    assert_includes response.body, feed_preview.url
    assert_includes response.body, feed_preview.feed_profile.name
  end

  test "should not show other user's preview" do
    other_user = create(:user)
    other_profile = create(:feed_profile, user: other_user)
    other_preview = create(:feed_preview, feed_profile: other_profile)

    sign_in_as(user)
    get feed_preview_url(other_preview)
    assert_redirected_to feeds_path
    follow_redirect!
    assert_includes response.body, "Preview not found"
  end

  test "should show processing status for pending preview" do
    sign_in_as(user)
    pending_preview = create(:feed_preview, feed_profile: feed_profile, status: :pending)

    get feed_preview_url(pending_preview)
    assert_response :success
    assert_includes response.body, "Generating Preview"
    assert_includes response.body, "spinner-border"
  end

  test "should show completed status for finished preview" do
    sign_in_as(user)
    completed_preview = create(:feed_preview, :completed, feed_profile: feed_profile)

    get feed_preview_url(completed_preview)
    assert_response :success
    assert_includes response.body, "Preview Complete"
    assert_includes response.body, "Sample post content"
  end

  test "should respond to turbo stream requests" do
    sign_in_as(user)

    get feed_preview_url(feed_preview, format: :turbo_stream)
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.content_type
  end

  test "should update preview by refreshing" do
    sign_in_as(user)
    original_preview = create(:feed_preview, :completed, feed_profile: feed_profile)

    assert_difference("FeedPreview.count", 0) do # old destroyed, new created
      patch feed_preview_url(original_preview)
    end

    assert_redirected_to feed_preview_path(FeedPreview.last)
    follow_redirect!
    assert_includes response.body, "Preview refresh started"
  end

  test "should handle missing preview gracefully" do
    sign_in_as(user)

    get "/previews/nonexistent-uuid"
    assert_redirected_to feeds_path
    follow_redirect!
    assert_includes response.body, "Preview not found"
  end

  test "should enqueue job for pending preview" do
    sign_in_as(user)

    assert_enqueued_with(job: FeedPreviewJob) do
      post feed_previews_url, params: {
        url: "https://example.com/feed.xml",
        feed_profile_id: feed_profile.id
      }
    end
  end

  test "should not enqueue job for existing recent preview" do
    sign_in_as(user)
    existing_preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml", status: :completed)

    assert_no_enqueued_jobs do
      post feed_previews_url, params: {
        url: "https://example.com/feed.xml",
        feed_profile_id: feed_profile.id
      }
    end

    assert_redirected_to feed_preview_path(existing_preview)
  end

  test "should handle feed profile not found" do
    sign_in_as(user)

    post feed_previews_url, params: {
      url: "https://example.com/feed.xml",
      feed_profile_id: 999999
    }

    assert_redirected_to feeds_path
    follow_redirect!
    assert_includes response.body, "Feed profile not found"
  end

  test "should show empty state for preview with no posts" do
    sign_in_as(user)
    empty_preview = create(:feed_preview, feed_profile: feed_profile, status: :completed, data: { posts: [] })

    get feed_preview_url(empty_preview)
    assert_response :success
    assert_includes response.body, "No posts found in this feed"
  end

  test "should display multiple posts correctly" do
    sign_in_as(user)
    multi_post_preview = create(:feed_preview, :with_multiple_posts, feed_profile: feed_profile)

    get feed_preview_url(multi_post_preview)
    assert_response :success
    assert_includes response.body, "Sample post content 1"
    assert_includes response.body, "Sample post content 2"
    assert_includes response.body, "Sample post content 3"
    assert_includes response.body, "Showing preview of 3 most recent posts"
  end

  test "should handle posts with attachments" do
    sign_in_as(user)
    posts_data = [{
      content: "Post with attachment",
      attachments: [
        { url: "https://example.com/image.jpg", type: "image" },
        "https://example.com/video.mp4"
      ]
    }]
    preview_with_attachments = create(:feed_preview, feed_profile: feed_profile,
                                    status: :completed, data: { posts: posts_data })

    get feed_preview_url(preview_with_attachments)
    assert_response :success
    assert_includes response.body, "Attachments:"
    assert_includes response.body, "https://example.com/image.jpg"
    assert_includes response.body, "https://example.com/video.mp4"
  end
end
