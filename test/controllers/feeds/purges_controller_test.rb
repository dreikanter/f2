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

  test "create schedules job and creates event" do
    sign_in_as(user)
    feed.update!(access_token: access_token)

    assert_enqueued_with(job: GroupPurgeJob, args: [feed.id]) do
      assert_difference("Event.count", 1) do
        post feed_purge_path(feed)
      end
    end

    assert_redirected_to feed_path(feed)
    assert_equal "Feed purge started for testgroup", flash[:notice]

    event = Event.last
    assert_equal "GroupPurgeStarted", event.type
    assert_equal user, event.user
    assert_equal feed, event.subject
    assert_equal "info", event.level
    assert_equal "testgroup", event.metadata["target_group"]
  end
end
