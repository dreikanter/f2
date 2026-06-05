require "test_helper"

class Feeds::RefreshesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user)
  end

  test "create requires authentication" do
    post feed_refresh_path(feed)
    assert_redirected_to new_session_path
  end

  test "create requires ownership" do
    sign_in_as(other_user)
    post feed_refresh_path(feed)
    assert_response :not_found
  end

  test "create schedules refresh job" do
    sign_in_as(user)

    assert_enqueued_with(job: FeedRefreshJob, args: [feed.id]) do
      post feed_refresh_path(feed)
    end

    assert_redirected_to feed_path(feed)
    assert_equal "Feed refresh started", flash[:notice]
  end
end
