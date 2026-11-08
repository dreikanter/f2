require "test_helper"

class Feeds::RefreshesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= regular_user
  end

  def feed
    @feed ||= create(:feed, :enabled, user: user)
  end

  def disabled_feed
    @disabled_feed ||= create(:feed, :disabled, user: user)
  end

  def draft_feed
    @draft_feed ||= create(:feed, :draft, user: user)
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

  test "create is not allowed for disabled feeds" do
    sign_in_as(user)
    post feed_refresh_path(disabled_feed)
    assert_redirected_to root_path
  end

  test "create is not allowed for webhook feeds" do
    sign_in_as(user)
    webhook_feed = create(:feed, :webhook, :enabled, user: user)

    assert_no_enqueued_jobs(only: FeedRefreshJob) do
      post feed_refresh_path(webhook_feed)
    end

    assert_redirected_to root_path
  end

  test "create is not allowed for draft feeds" do
    sign_in_as(user)
    post feed_refresh_path(draft_feed)
    assert_redirected_to root_path
  end

  test "create schedules refresh job" do
    sign_in_as(user)

    assert_enqueued_with(job: FeedRefreshJob, args: [feed.id]) do
      post feed_refresh_path(feed)
    end

    assert_redirected_to feed_path(feed, refresh_after: "none")
    assert_nil flash[:notice]
  end

  test "create responds with turbo stream" do
    sign_in_as(user)

    assert_enqueued_with(job: FeedRefreshJob, args: [feed.id]) do
      post feed_refresh_path(feed), as: :turbo_stream
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action='replace'][target='header_feed_#{feed.id}']" do
      assert_select '[data-key="feed.refreshing"] svg'
    end
    assert_select "#flash-messages", count: 0
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

  test "#create should show progress beside the title after an HTML redirect" do
    sign_in_as(user)
    post feed_refresh_path(feed)
    location = response.location
    follow_redirect!
    assert_select 'h1 + [data-key="feed.refresh-status"] [data-key="feed.refreshing"]'

    create(:event, type: "feed_refresh", subject: feed, user: user,
                   metadata: { status: "completed", stats: { new_posts: 2 } })
    get location
    assert_select '[data-key="feed.refreshing"]', count: 0
    assert_select '[data-key="feed.refresh-status"]', text: ""
    assert_select '#feed-live-content [data-key="events.posts_count"]', text: "2 new posts"
  end

  # rate_limit counts in Rails.cache, which is the no-op :null_store in tests.
  # Delegate the captured store's increment to a real MemoryStore so the limit
  # actually engages for the duration of the block.
  def with_rate_limit_cache(&block)
    store = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.cache_store.stub(:increment, ->(*args, **kwargs) { store.increment(*args, **kwargs) }, &block)
  end
end
