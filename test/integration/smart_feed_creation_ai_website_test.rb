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
    @credential ||= create(:ai_credential, :active, user: user,
                           available_models: [{ "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" }])
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
  # returns / raises the prescripted result. Exposes #credential like the
  # real client so the loader can resolve the model. Block-scoped, no
  # monkey-patching of stage classes.
  def with_llm_client(result, credential: self.credential, &block)
    fake_client = Class.new do
      attr_reader :credential

      def initialize(result, credential)
        @result = result
        @credential = credential
      end

      def call(_ctx, **_opts)
        case @result
        when Exception then raise @result
        when Hash then LlmClient::Result.new(payload: @result, usage_id: 1)
        else raise ArgumentError, "unsupported stub result: #{@result.class}"
        end
      end
    end.new(result, credential)

    LlmClient.stub(:for, ->(*_args) { fake_client }, &block)
  end

  def detect(url)
    stub_request(:get, url).to_return(status: 200, body: "<html><body>no rss here</body></html>")
    post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs
  end

  test "#post should walk the AI happy path: detect, preview, save enabled" do
    sign_in_as(user)
    access_token
    credential

    with_llm_client({ "items" => sample_items }) do
      with_memory_cache do
        detect(ai_url)

      get feed_identifications_path, params: { input: ai_url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_includes response.body, "AI page reader"

      post feed_preview_path(profile_key: "llm_website_extractor", "params" => { "url" => ai_url },
                             ai_credential_id: credential.id, ai_model: "claude-sonnet-4-6")
      assert_response :success
      perform_enqueued_jobs

      preview = FeedPreview.last
      assert_predicate preview, :ready?

      assert_difference("Feed.count", 1) do
        post feeds_path, params: {
          feed: {
            url: ai_url,
            name: "No-RSS Blog",
            feed_profile_key: "llm_website_extractor",
            access_token_id: access_token.id,
            target_group: "testgroup",
            schedule_interval: "1h",
            ai_credential_id: credential.id,
            ai_model: "claude-sonnet-4-6"
          },
          enable_feed: "1"
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
      post feed_preview_path(profile_key: "llm_website_extractor", "params" => { "url" => ai_url })

      assert_response :success
      assert_select "[data-key='credentials.gate']"
      assert_no_enqueued_jobs
    end
  end

  test "#post should accept save-anyway after a preview failure and land as draft" do
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
          ai_credential_id: credential.id
        },
        enable_feed: "0"
      }
    end

    assert_equal "draft", Feed.last.state
  end
end
