require "test_helper"

class Feeds::PreviewsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user, feed_profile_key: "rss", params: { "url" => "https://example.com/feed.xml" })
  end

  def show_params
    { profile_key: "rss", params: { url: "https://example.com/feed.xml" } }
  end

  def with_memory_cache
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = previous
  end

  def sample_preview
    FeedPreviewService::Preview.new(
      posts: [
        FeedPreviewService::PostDraft.new(
          title: "Sample title",
          body: "Sample body",
          supplementary: [],
          images: [],
          source_url: "https://example.com/post-1",
          published_at: Time.current,
          uid: "uid-1"
        )
      ],
      generated_at: Time.current,
      source_summary: "RSS: example.com",
      used_ai: false,
      llm_usage_id: nil,
      preview_token: "token-abc"
    )
  end

  test "#show should require authentication" do
    get feed_live_preview_path(feed), params: show_params
    assert_redirected_to new_session_path
  end

  test "#show should 404 for another user's feed" do
    sign_in_as(other_user)
    get feed_live_preview_path(feed), params: show_params
    assert_response :not_found
  end

  test "#show should enqueue preview job and render loading partial on cache miss" do
    sign_in_as(user)

    with_memory_cache do
      assert_enqueued_with(job: FeedPreviewJob) do
        get feed_live_preview_path(feed), params: show_params
      end

      assert_response :success
      assert_select "[data-key='preview.loading']"
      assert_select "turbo-frame#feed-preview"
    end
  end

  test "#show should render preview partial on cache hit" do
    sign_in_as(user)

    with_memory_cache do
      # Warm the cache by hitting show once to learn its cache key
      get feed_live_preview_path(feed), params: show_params
      cache_key = cache_key_from_logs(user_id: user.id, feed_id: feed.id, profile_key: "rss", params: { "url" => "https://example.com/feed.xml" })
      Rails.cache.write(cache_key, sample_preview)
      clear_enqueued_jobs

      assert_no_enqueued_jobs do
        get feed_live_preview_path(feed), params: show_params
      end

      assert_response :success
      assert_select "[data-key='preview.success']"
      assert_select "[data-key='preview.post.0']"
    end
  end

  test "#show should render failed partial when cache holds a failure marker" do
    sign_in_as(user)

    with_memory_cache do
      get feed_live_preview_path(feed), params: show_params
      cache_key = cache_key_from_logs(user_id: user.id, feed_id: feed.id, profile_key: "rss", params: { "url" => "https://example.com/feed.xml" })
      Rails.cache.write(cache_key, { error: "SourceUnreachable", message: "Could not reach the source." })
      clear_enqueued_jobs

      get feed_live_preview_path(feed), params: show_params

      assert_response :success
      assert_select "[data-key='preview.failed']"
      assert_select "[data-key='preview.failed.retry']"
      assert_select "[data-key='preview.failed.save-disabled']"
    end
  end

  test "#show should accept the draft sentinel for new feeds" do
    sign_in_as(user)

    with_memory_cache do
      assert_enqueued_with(job: FeedPreviewJob) do
        get feed_live_preview_path("draft"), params: show_params
      end

      assert_response :success
      assert_select "[data-key='preview.loading']"
    end
  end

  test "#show should answer turbo_stream requests with a frame update" do
    sign_in_as(user)

    with_memory_cache do
      get feed_live_preview_path(feed),
          params: show_params,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
      assert_includes response.body, "feed-preview"
    end
  end

  test "#create should bust cache and re-enqueue with refresh" do
    sign_in_as(user)

    with_memory_cache do
      get feed_live_preview_path(feed), params: show_params
      cache_key = cache_key_from_logs(user_id: user.id, feed_id: feed.id, profile_key: "rss", params: { "url" => "https://example.com/feed.xml" })
      Rails.cache.write(cache_key, sample_preview)
      clear_enqueued_jobs

      assert_enqueued_with(job: FeedPreviewJob) do
        post feed_live_preview_path(feed), params: show_params
      end

      assert_response :success
      assert_select "[data-key='preview.loading']"
      assert_nil Rails.cache.read(cache_key)
    end
  end

  test "#destroy should clear the cached preview" do
    sign_in_as(user)

    with_memory_cache do
      get feed_live_preview_path(feed), params: show_params
      cache_key = cache_key_from_logs(user_id: user.id, feed_id: feed.id, profile_key: "rss", params: { "url" => "https://example.com/feed.xml" })
      Rails.cache.write(cache_key, sample_preview)

      delete feed_live_preview_path(feed),
             params: show_params,
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_nil Rails.cache.read(cache_key)
    end
  end

  private

  # Mirrors the cache key built by Feeds::PreviewsController so the test can
  # populate the cache without depending on private controller helpers.
  def cache_key_from_logs(user_id:, feed_id:, profile_key:, params:)
    namespace = feed_id == "draft" ? "draft:#{user_id}" : "feed:#{feed_id}"
    canonical = params.deep_stringify_keys.sort.to_h.to_json
    "preview:#{namespace}:#{profile_key}:#{Digest::SHA256.hexdigest(canonical)}"
  end
end
