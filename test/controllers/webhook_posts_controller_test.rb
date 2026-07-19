require "test_helper"

class WebhookPostsControllerTest < ActionDispatch::IntegrationTest
  def feed
    @feed ||= create(:feed, :webhook, :enabled)
  end

  def endpoint
    @endpoint ||= create(:webhook_endpoint, feed: feed)
  end

  def hook_url
    webhook_posts_path
  end

  def authorization_headers(token = endpoint.encrypted_token)
    { "Authorization" => "Bearer #{token}" }
  end

  def post_hook(params:, token: endpoint.encrypted_token, as: nil, headers: {})
    options = { params: params, headers: authorization_headers(token).merge(headers) }
    options[:as] = as if as
    post hook_url, **options
  end

  def response_json
    JSON.parse(response.body)
  end

  test "controller should use the API-only stack" do
    assert_operator WebhookPostsController, :<, ActionController::API
  end

  test "#create should enqueue a post from a JSON payload" do
    assert_difference ["FeedEntry.count", "Post.count"], 1 do
      post_hook params: { content: "Hello world" }, as: :json
    end

    assert_response :created
    assert_equal "enqueued", response_json["status"]
    assert response_json["uid"].present?
    assert_nil response_json["warnings"]
  end

  test "#create should enqueue a post from a form-encoded payload" do
    post_hook params: { content: "Hello world" }

    assert_response :created
    assert_equal "enqueued", response_json["status"]
  end

  test "#create should accept the full payload shape" do
    post_hook params: {
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
    post_hook params: { content: "a" * (Post::MAX_CONTENT_LENGTH + 1) }, as: :json

    assert_response :created
    assert_equal ["content_truncated"], response_json["warnings"]
  end

  test "#create should answer duplicate for a redelivered uid" do
    post_hook params: { content: "Hello", uid: "article-42" }, as: :json

    assert_no_difference ["FeedEntry.count", "Post.count"] do
      post_hook params: { content: "Hello", uid: "article-42" }, as: :json
    end

    assert_response :ok
    assert_equal "duplicate", response_json["status"]
    assert_equal "article-42", response_json["uid"]
  end

  test "#create should reject an invalid payload without persisting" do
    assert_no_difference ["FeedEntry.count", "Post.count"] do
      post_hook params: { comments: ["No content here"] }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "invalid", response_json["status"]
    assert_includes response_json["errors"], "no_content_or_images"
  end

  test "#create should reject unknown body fields including token" do
    assert_no_difference ["FeedEntry.count", "Post.count"] do
      post_hook params: { content: "Hello", token: "caller-value" }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "invalid", response_json["status"]
    assert response_json["errors"].any?
  end

  test "#create should require an Authorization header" do
    post hook_url, params: { content: "Hello" }, as: :json

    assert_response :unauthorized
    assert_equal "unauthorized", response_json["status"]
    assert_equal 'Bearer realm="webhook"', response.headers["WWW-Authenticate"]
  end

  test "#create should reject non-bearer authentication" do
    post hook_url, params: { content: "Hello" },
                   headers: { "Authorization" => "Basic abc123" }, as: :json

    assert_response :unauthorized
    assert_equal "unauthorized", response_json["status"]
  end

  test "#create should reject an unknown token" do
    post_hook params: { content: "Hello" }, token: "a" * 43, as: :json

    assert_response :unauthorized
    assert_equal "unauthorized", response_json["status"]
  end

  test "#create should reject a malformed token without querying encrypted values" do
    queried = false

    WebhookEndpoint.stub(:find_by, ->(*) { queried = true }) do
      post_hook params: { content: "Hello" }, token: "too-short", as: :json
    end

    assert_response :unauthorized
    assert_equal "unauthorized", response_json["status"]
    assert_not queried
  end

  test "#create should reject the old token after rotation" do
    old_token = endpoint.encrypted_token
    endpoint.rotate!

    post_hook params: { content: "Hello" }, token: old_token, as: :json

    assert_response :unauthorized
  end

  test "#create should answer feed_not_enabled for a draft feed" do
    feed.update!(state: :draft)

    post_hook params: { content: "Hello" }, as: :json

    assert_response :conflict
    assert_equal "feed_not_enabled", response_json["status"]
  end

  test "#create should answer feed_not_enabled for a disabled feed" do
    feed.update!(state: :disabled)

    post_hook params: { content: "Hello" }, as: :json

    assert_response :conflict
  end

  test "#create should reject an oversized body before parsing" do
    post_hook params: { content: "a" * (WebhookPostsController::MAX_BODY_BYTES + 1024) }, as: :json

    assert_response :content_too_large
  end

  test "#oversized_body? should inspect actual bytes and rewind the body" do
    body = StringIO.new("a" * (WebhookPostsController::MAX_BODY_BYTES + 1))
    request = Struct.new(:content_length, :body).new(nil, body)
    controller = WebhookPostsController.new

    controller.stub(:request, request) do
      assert controller.send(:oversized_body?)
    end

    assert_equal 0, body.pos
  end

  test "#create should throttle a chatty endpoint with Retry-After" do
    freeze_time do
      burst = RateLimit.capacity(:webhook_ingest, :request)
      burst.times { post_hook params: { content: "Hello" }, as: :json }

      post_hook params: { content: "One too many" }, as: :json

      assert_response :too_many_requests
      assert_equal "throttled", response_json["status"]
      assert response.headers["Retry-After"].to_i.positive?
    end
  end

  test "#create should not require an application session or CSRF token" do
    post_hook params: { content: "Hello" }, as: :json

    assert_response :created
  end

  test "#create should answer bad_request JSON for a malformed body" do
    post hook_url, params: "{not json",
                   headers: authorization_headers.merge("Content-Type" => "application/json")

    assert_response :bad_request
    assert_equal "bad_request", response_json["status"]
  end

  test "#create should ignore the outdated-browser gate" do
    old_browser = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.60 Safari/537.36"

    post_hook params: { content: "Hello" }, headers: { "User-Agent" => old_browser }

    assert_response :created
    assert_equal "enqueued", response_json["status"]
  end
end
