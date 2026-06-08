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

  test "create responds with turbo stream" do
    sign_in_as(user)

    assert_enqueued_with(job: FeedRefreshJob, args: [feed.id]) do
      post feed_refresh_path(feed), as: :turbo_stream
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
  end

  test "create throttles repeated refreshes for the same feed" do
    sign_in_as(user)

    with_rate_limit_cache do
      10.times do
        post feed_refresh_path(feed), as: :turbo_stream
        assert_response :success
      end

      assert_no_enqueued_jobs do
        post feed_refresh_path(feed), as: :turbo_stream
      end
      assert_response :too_many_requests
    end
  end

  # rate_limit counts in Rails.cache, which is the no-op :null_store in tests.
  # Delegate the captured store's increment to a real MemoryStore so the limit
  # actually engages for the duration of the block.
  def with_rate_limit_cache(&block)
    store = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.cache_store.stub(:increment, ->(*args, **kwargs) { store.increment(*args, **kwargs) }, &block)
  end
end
