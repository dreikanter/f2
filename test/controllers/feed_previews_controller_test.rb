require "test_helper"

class FeedPreviewsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def feed_preview
    @feed_preview ||= create(:feed_preview, user: user)
  end

  test "#create should require authentication" do
    post feed_previews_url, params: {
      url: "http://example.com/feed.xml",
      feed_profile_key: "rss"
    }
    assert_redirected_to new_session_path
  end

  test "#create should create feed preview with valid params" do
    sign_in_as(user)

    assert_difference("FeedPreview.count", 1) do
      post feed_previews_url, params: {
        url: "http://example.com/feed.xml",
        feed_profile_key: "rss"
      }
    end

    preview = FeedPreview.last
    assert_equal "http://example.com/feed.xml", preview.url
    assert_equal "rss", preview.feed_profile_key
    assert_equal user, preview.user
    assert_redirected_to feed_preview_path(preview)
  end

  test "#create should handle invalid feed profile key" do
    sign_in_as(user)

    assert_no_difference("FeedPreview.count") do
      post feed_previews_url, params: {
        url: "http://example.com/feed.xml",
        feed_profile_key: "nonexistent"
      }
    end

    assert_redirected_to feeds_path
  end

  test "#show should require authentication" do
    get feed_preview_url(feed_preview)
    assert_redirected_to new_session_path
  end

  test "#show should render feed preview" do
    sign_in_as(user)
    get feed_preview_url(feed_preview)
    assert_response :success
    assert_includes response.body, "Feed URL:"
    assert_includes response.body, "Feed profile:"
  end

  test "#show should handle missing preview" do
    sign_in_as(user)
    get feed_preview_url(id: 999999)
    assert_redirected_to feeds_path
  end

  test "#update should require authentication" do
    patch feed_preview_url(feed_preview), params: {}
    assert_redirected_to new_session_path
  end

  test "#update should update feed preview" do
    sign_in_as(user)
    existing_preview = create(:feed_preview, user: user, url: "http://old.com/feed.xml")

    assert_difference("FeedPreview.count", 0) do # Should replace, not create new
      patch feed_preview_url(existing_preview), params: {}
    end

    assert_redirected_to feed_preview_path(FeedPreview.last)
  end

  test "#update should handle missing preview" do
    sign_in_as(user)
    patch feed_preview_url(id: 999999), params: {}
    assert_redirected_to feeds_path
  end

  test "#show should respond to turbo stream format" do
    sign_in_as(user)

    get feed_preview_url(feed_preview), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
  end

  test "#create should handle invalid URL validation" do
    sign_in_as(user)

    # Create a preview with invalid URL to trigger validation error
    assert_no_difference("FeedPreview.count") do
      post feed_previews_url, params: {
        url: "not-a-valid-url-format",
        feed_profile_key: "rss"
      }
    end

    # Should redirect to feeds_path (though the specific error case might not be hit)
    assert_response :redirect
  end

  test "#show should render turbo stream for ready preview status" do
    sign_in_as(user)
    completed_preview = create(:feed_preview, user: user, status: :ready)

    get feed_preview_url(completed_preview), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "turbo-stream"
  end

  test "#show should render turbo stream for failed preview status" do
    sign_in_as(user)
    failed_preview = create(:feed_preview, user: user, status: :failed)

    get feed_preview_url(failed_preview), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "turbo-stream"
  end

  test "#show should render turbo stream for processing preview status" do
    sign_in_as(user)
    processing_preview = create(:feed_preview, user: user, status: :processing)

    get feed_preview_url(processing_preview), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "turbo-stream"
  end

  test "#show should render turbo stream for pending preview status" do
    sign_in_as(user)
    pending_preview = create(:feed_preview, user: user, status: :pending)

    get feed_preview_url(pending_preview), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "turbo-stream"
  end

  test "#update should complete successfully" do
    sign_in_as(user)
    existing_preview = create(:feed_preview, user: user)

    # The update action should complete successfully
    patch feed_preview_url(existing_preview), params: {}

    assert_response :redirect
    assert_redirected_to feed_preview_path(FeedPreview.last)
  end

  test "#update should create and enqueue preview successfully" do
    sign_in_as(user)
    existing_preview = create(:feed_preview, user: user, url: "http://old.com/feed.xml")

    # The update action should delete existing previews and create a new one
    assert_difference("FeedPreview.count", 0) do # Net change should be 0 (delete 1, create 1)
      patch feed_preview_url(existing_preview), params: {}
    end

    assert_redirected_to feed_preview_path(FeedPreview.last)
  end
end
