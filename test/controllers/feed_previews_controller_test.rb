require "test_helper"

class FeedPreviewsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def feed_profile
    @feed_profile ||= create(:feed_profile, user: user)
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
end
