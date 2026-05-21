require "test_helper"

# Integration test for User Story 2 (AI website extraction).
# Covers the credential-present path, the credential-gate path, and the
# preview-failure "save anyway" path. Stubs the LLM call at the
# Loader::LlmLoader seam (per LlmClient contract: stage tests stub the
# client, not RubyLLM directly).
class SmartFeedCreationAiWebsiteTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def credential
    @credential ||= create(:llm_credential, :active, user: user)
  end

  def ai_url
    "https://no-rss-example.com/blog"
  end

  def sample_items
    [
      { "uid" => "https://no-rss-example.com/blog/post-1",
        "title" => "First post",
        "body" => "Hello world",
        "source_url" => "https://no-rss-example.com/blog/post-1",
        "supplementary" => [],
        "images" => [],
        "published_at" => "2026-05-10T00:00:00Z" }
    ]
  end

  def with_memory_cache
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = previous
  end

  # Stubs LlmClient.for so the loader receives a fake client whose #call
  # returns / raises the prescripted result. Block-scoped, no
  # monkey-patching of stage classes.
  def with_llm_client(result, &block)
    fake_client = Class.new do
      def initialize(result) = (@result = result)
      def call(**_args)
        case @result
        when Exception then raise @result
        when Hash then LlmClient::Result.new(payload: @result, usage_id: 1)
        else raise ArgumentError, "unsupported stub result: #{@result.class}"
        end
      end
    end.new(result)

    LlmClient.stub(:for, ->(*_args) { fake_client }, &block)
  end

  def detect(url)
    stub_request(:get, url).to_return(status: 200, body: "<html><body>no rss here</body></html>")
    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs
  end

  test "#post should walk the AI happy path: detect, preview, save enabled" do
    sign_in_as(user)
    access_token
    credential

    with_llm_client({ "items" => sample_items }) do
      with_memory_cache do
        detect(ai_url)

      get feed_identifications_path, params: { url: ai_url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_includes response.body, "AI page reader"

      get feed_live_preview_path("draft"),
          params: { profile_key: "llm_website_extractor", params: { url: ai_url } }
      assert_response :success
      perform_enqueued_jobs

      preview = FeedPreviewService.call(
        user: user,
        profile_key: "llm_website_extractor",
        params: { "url" => ai_url },
        llm_credential: credential
      )
      assert preview.preview_token.present?

      assert_difference("Feed.count", 1) do
        post feeds_path, params: {
          feed: {
            url: ai_url,
            name: "No-RSS Blog",
            feed_profile_key: "llm_website_extractor",
            access_token_id: access_token.id,
            target_group: "testgroup",
            schedule_interval: "1h",
            llm_credential_id: credential.id
          },
          enable_feed: "1",
          preview_token: preview.preview_token
        }
      end

      assert_equal "enabled", Feed.last.state
      end
    end
  end

  test "#show should gate on credentials when an AI profile has no usable credential" do
    sign_in_as(user)
    # no credential created

    with_memory_cache do
      get feed_live_preview_path("draft"),
          params: { profile_key: "llm_website_extractor", params: { url: ai_url } }

      assert_response :success
      assert_select "[data-key='credentials.gate']"
      assert_no_enqueued_jobs
    end
  end

  test "#post should accept save-anyway after a preview failure and land disabled" do
    sign_in_as(user)
    access_token
    credential

    assert_difference("Feed.count", 1) do
      post feeds_path, params: {
        feed: {
          url: ai_url,
          name: "No-RSS Blog",
          feed_profile_key: "llm_website_extractor",
          access_token_id: access_token.id,
          target_group: "testgroup",
          schedule_interval: "1h",
          llm_credential_id: credential.id
        },
        enable_feed: "0"
      }
    end

    assert_equal "disabled", Feed.last.state
  end
end
