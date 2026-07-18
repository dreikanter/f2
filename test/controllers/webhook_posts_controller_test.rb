require "test_helper"

class WebhookPostsControllerTest < ActionDispatch::IntegrationTest
  def feed
    @feed ||= create(:feed, :webhook, :enabled)
  end

  def endpoint
    @endpoint ||= create(:webhook_endpoint, feed: feed)
  end

  def hook_url
    webhook_posts_path(endpoint.encrypted_token)
  end

  def response_json
    JSON.parse(response.body)
  end

  test "#create should enqueue a post from a JSON payload" do
    assert_difference ["FeedEntry.count", "Post.count"], 1 do
      post hook_url, params: { content: "Hello world" }, as: :json
    end

    assert_response :created
    assert_equal "enqueued", response_json["status"]
    assert response_json["uid"].present?
    assert_nil response_json["warnings"]
  end

  test "#create should enqueue a post from a form-encoded payload" do
    post hook_url, params: { content: "Hello world" }

    assert_response :created
    assert_equal "enqueued", response_json["status"]
  end

  test "#create should accept the full payload shape" do
    post hook_url, params: {
      content: "Look at this",
      source_url: "https://example.com/article",
      images: ["https://example.com/pic.jpg"],
      comments: ["First comment"],
      uid: "article-42",
      published_at: "2026-07-11T12:00:00Z"
    }, as: :json

    assert_response :created
    assert_equal "article-42", response_json["uid"]

    post_record = feed.posts.sole
    assert_equal ["https://example.com/pic.jpg"], post_record.attachment_urls
    assert_equal ["First comment"], post_record.comments
  end

  test "#create should include warnings when content gets truncated" do
    post hook_url, params: { content: "a" * (Post::MAX_CONTENT_LENGTH + 1) }, as: :json

    assert_response :created
    assert_equal ["content_truncated"], response_json["warnings"]
  end

  test "#create should answer duplicate for a redelivered uid" do
    post hook_url, params: { content: "Hello", uid: "article-42" }, as: :json

    assert_no_difference ["FeedEntry.count", "Post.count"] do
      post hook_url, params: { content: "Hello", uid: "article-42" }, as: :json
    end

    assert_response :ok
    assert_equal "duplicate", response_json["status"]
    assert_equal "article-42", response_json["uid"]
  end

  test "#create should reject an invalid payload without persisting" do
    assert_no_difference ["FeedEntry.count", "Post.count"] do
      post hook_url, params: { comments: ["No content here"] }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "invalid", response_json["status"]
    assert_includes response_json["errors"], "no_content_or_images"
  end

  test "#create should answer not_found for an unknown token" do
    post webhook_posts_path("unknown-token"), params: { content: "Hello" }, as: :json

    assert_response :not_found
    assert_equal "not_found", response_json["status"]
  end

  test "#create should answer not_found after rotation" do
    old_url = hook_url
    endpoint.rotate!

    post old_url, params: { content: "Hello" }, as: :json

    assert_response :not_found
  end

  test "#create should answer feed_not_enabled for a draft feed" do
    feed.update!(state: :draft)

    post hook_url, params: { content: "Hello" }, as: :json

    assert_response :conflict
    assert_equal "feed_not_enabled", response_json["status"]
  end

  test "#create should answer feed_not_enabled for a disabled feed" do
    feed.update!(state: :disabled)

    post hook_url, params: { content: "Hello" }, as: :json

    assert_response :conflict
  end

  test "#create should reject an oversized body before parsing" do
    post hook_url, params: { content: "a" * (WebhookPostsController::MAX_BODY_BYTES + 1024) }, as: :json

    assert_response :content_too_large
  end

  test "#create should throttle a chatty endpoint with Retry-After" do
    freeze_time do
      burst = RateLimit.capacity(:webhook_ingest, :request)
      burst.times { post hook_url, params: { content: "Hello" }, as: :json }

      post hook_url, params: { content: "One too many" }, as: :json

      assert_response :too_many_requests
      assert_equal "throttled", response_json["status"]
      assert response.headers["Retry-After"].to_i.positive?
    end
  end

  test "#create should not require authentication or CSRF" do
    post hook_url, params: { content: "Hello" }, as: :json

    assert_response :created
  end
end
