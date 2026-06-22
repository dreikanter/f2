require "test_helper"

class Feeds::PurgesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user, target_group: "testgroup")
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  test "create requires authentication" do
    post feed_purge_path(feed)
    assert_redirected_to new_session_path
  end

  test "create requires ownership" do
    sign_in_as(other_user)
    post feed_purge_path(feed)
    assert_response :not_found
  end

  test "create schedules job and redirects" do
    sign_in_as(user)
    feed.update!(access_token: access_token)

    assert_enqueued_with(job: WithdrawAllPostsJob, args: [feed.id, user.id]) do
      post feed_purge_path(feed)
    end

    assert_redirected_to feed_path(feed)
    assert_equal "Feed purge started for testgroup", flash[:notice]
  end
end
