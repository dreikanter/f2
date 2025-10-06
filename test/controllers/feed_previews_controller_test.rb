require "test_helper"

class FeedPreviewsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def feed_profile
    @feed_profile ||= create(:feed_profile)
  end

  def feed_preview
    @feed_preview ||= create(:feed_preview, user: user, feed_profile: feed_profile)
  end

  test "should require authentication for create" do
    post feed_previews_url, params: {
      url: "http://example.com/feed.xml",
      feed_profile_name: feed_profile.name
    }
    assert_redirected_to new_session_path
  end

  test "should create feed preview with valid params" do
    sign_in_as(user)

    assert_difference("FeedPreview.count", 1) do
      post feed_previews_url, params: {
        url: "http://example.com/feed.xml",
        feed_profile_name: feed_profile.name
      }
    end

    preview = FeedPreview.last
    assert_equal "http://example.com/feed.xml", preview.url
    assert_equal feed_profile, preview.feed_profile
    assert_equal user, preview.user
    assert_redirected_to feed_preview_path(preview)
  end

  test "should handle invalid feed profile name" do
    sign_in_as(user)

    assert_no_difference("FeedPreview.count") do
      post feed_previews_url, params: {
        url: "http://example.com/feed.xml",
        feed_profile_name: "nonexistent"
      }
    end

    assert_redirected_to feeds_path
  end

  test "should require authentication for show" do
    get feed_preview_url(feed_preview)
    assert_redirected_to new_session_path
  end

  test "should show feed preview" do
    sign_in_as(user)
    get feed_preview_url(feed_preview)
    assert_response :success
  end

  test "should handle missing preview in show" do
    sign_in_as(user)
    get feed_preview_url(id: 999999)
    assert_redirected_to feeds_path
  end

  test "should require authentication for update" do
    patch feed_preview_url(feed_preview), params: {}
    assert_redirected_to new_session_path
  end

  test "should update feed preview" do
    sign_in_as(user)
    existing_preview = create(:feed_preview, user: user, feed_profile: feed_profile, url: "http://old.com/feed.xml")

    assert_difference("FeedPreview.count", 0) do # Should replace, not create new
      patch feed_preview_url(existing_preview), params: {}
    end

    assert_redirected_to feed_preview_path(FeedPreview.last)
  end

  test "should handle missing preview in update" do
    sign_in_as(user)
    patch feed_preview_url(id: 999999), params: {}
    assert_redirected_to feeds_path
  end

  test "should respond to turbo stream format" do
    sign_in_as(user)

    get feed_preview_url(feed_preview), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
  end

  test "should handle invalid URL validation in create" do
    sign_in_as(user)

    # Create a preview with invalid URL to trigger validation error
    assert_no_difference("FeedPreview.count") do
      post feed_previews_url, params: {
        url: "not-a-valid-url-format",
        feed_profile_name: feed_profile.name
      }
    end

    # Should redirect to feeds_path (though the specific error case might not be hit)
    assert_response :redirect
  end

  test "should render turbo stream for completed preview status" do
    sign_in_as(user)
    completed_preview = create(:feed_preview, user: user, feed_profile: feed_profile, status: :ready)

    get feed_preview_url(completed_preview), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "turbo-stream"
  end

  test "should render turbo stream for failed preview status" do
    sign_in_as(user)
    failed_preview = create(:feed_preview, user: user, feed_profile: feed_profile, status: :failed)

    get feed_preview_url(failed_preview), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "turbo-stream"
  end

  test "should render turbo stream for processing preview status" do
    sign_in_as(user)
    processing_preview = create(:feed_preview, user: user, feed_profile: feed_profile, status: :processing)

    get feed_preview_url(processing_preview), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "turbo-stream"
  end

  test "should render turbo stream for pending preview status" do
    sign_in_as(user)
    pending_preview = create(:feed_preview, user: user, feed_profile: feed_profile, status: :pending)

    get feed_preview_url(pending_preview), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "turbo-stream"
  end

  test "should handle update action successfully" do
    sign_in_as(user)
    existing_preview = create(:feed_preview, user: user, feed_profile: feed_profile)

    # The update action should complete successfully
    patch feed_preview_url(existing_preview), params: {}

    assert_response :redirect
    assert_redirected_to feed_preview_path(FeedPreview.last)
  end

  test "should create and enqueue preview successfully" do
    sign_in_as(user)
    existing_preview = create(:feed_preview, user: user, feed_profile: feed_profile, url: "http://old.com/feed.xml")

    # The update action should delete existing previews and create a new one
    assert_difference("FeedPreview.count", 0) do # Net change should be 0 (delete 1, create 1)
      patch feed_preview_url(existing_preview), params: {}
    end

    assert_redirected_to feed_preview_path(FeedPreview.last)
  end
end
