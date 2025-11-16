require "test_helper"

class FeedDetailsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    # Use memory store for cache-dependent tests (test env uses null_store by default)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @original_cache
  end

  def user
    @user ||= create(:user)
  end

  def cache_key(url)
    FeedIdentificationCache.key_for(user.id, url)
  end

  test "#create should require authentication" do
    post feed_details_path, params: { url: "http://example.com/feed.xml" }
    assert_redirected_to new_session_path
  end

  test "#create should create cache entry and enqueue job for valid URL" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    assert_enqueued_with(job: FeedDetailsJob, args: [user.id, url]) do
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type

    cached_data = Rails.cache.read(cache_key(url))
    assert_not_nil cached_data
    assert_equal "processing", cached_data[:status]
    assert_equal url, cached_data[:url]
    assert_not_nil cached_data[:started_at]
  end

  test "#create should reuse existing cache entry if present" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    Rails.cache.write(
      cache_key(url),
      { status: "processing", url: url, started_at: Time.current },
      expires_in: 10.minutes
    )

    assert_no_enqueued_jobs do
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
  end

  test "#create should reuse successful identification from cache" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    Rails.cache.write(
      cache_key(url),
      {
        status: "success",
        url: url,
        feed_profile_key: "youtube",
        title: "Example Channel"
      },
      expires_in: 10.minutes
    )

    assert_no_enqueued_jobs do
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, "Feed identified: youtube"
    assert_includes response.body, 'data-identification-state="complete"'
  end

  test "#create should restart identification for failed cache entry" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    Rails.cache.write(
      cache_key(url),
      { status: "failed", url: url, error: "Previous attempt failed" },
      expires_in: 10.minutes
    )

    assert_enqueued_with(job: FeedDetailsJob, args: [user.id, url]) do
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, "Checking this feed"
  end

  test "#create should return error for invalid URL" do
    sign_in_as(user)

    post feed_details_path, params: { url: "not-a-url" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Please enter a valid URL"
    assert_includes response.body, 'target="feed-form"'
  end

  test "#create should return error for empty URL" do
    sign_in_as(user)

    post feed_details_path, params: { url: "" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Please enter a valid URL"
  end

  test "#create should return loading state turbo stream" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "turbo-stream"
    assert_includes response.body, 'action="replace"'
    assert_includes response.body, 'target="feed-form"'
    assert_includes response.body, "Checking this feed"
  end

  test "#show should require authentication" do
    get feed_details_path, params: { url: "http://example.com/feed.xml" }
    assert_redirected_to new_session_path
  end

  test "#show should return processing state when status is processing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    Rails.cache.write(
      cache_key(url),
      { status: "processing", url: url, started_at: Time.current },
      expires_in: 10.minutes
    )

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Checking this feed"
  end

  test "#show should return timeout error when processing exceeds threshold" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    Rails.cache.write(
      cache_key(url),
      { status: "processing", url: url, started_at: 31.seconds.ago },
      expires_in: 10.minutes
    )

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "taking longer than expected"
    assert_nil Rails.cache.read(cache_key(url)), "Cache entry should be deleted on timeout"
  end

  test "#show should return expanded form when status is success" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    Rails.cache.write(
      cache_key(url),
      { status: "success", url: url, feed_profile_key: "rss", title: "Test Feed" },
      expires_in: 10.minutes
    )

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, 'action="replace"'
    assert_includes response.body, 'target="feed-form"'
  end

  test "#show should return error when status is failed" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    Rails.cache.write(
      cache_key(url),
      { status: "failed", url: url, error: "Could not identify feed profile" },
      expires_in: 10.minutes
    )

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Could not identify feed profile"
    assert_includes response.body, 'data-identification-state="error"'
  end

  test "#show should return error when cache entry is missing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Identification session expired"
  end

  test "#show should use default error message when failed status has no error" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    Rails.cache.write(
      cache_key(url),
      { status: "failed", url: url },
      expires_in: 10.minutes
    )

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "We couldn&#39;t identify a feed profile for this URL"
  end
end
