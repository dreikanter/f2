require "test_helper"

class FeedPreviewWorkflowTest < ActiveSupport::TestCase
  RUN_ID = "11111111-1111-4111-8111-111111111111"
  NEXT_RUN_ID = "22222222-2222-4222-8222-222222222222"
  AI_RUN_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

  FEED_URL = "https://example.com/feed.xml"

  def user
    @user ||= create(:user)
  end

  def feed_preview
    @feed_preview ||= create(:feed_preview, user: user, feed_profile_key: "rss",
                             params: { "url" => FEED_URL }, status: :pending, run_id: RUN_ID)
  end

  # Non-ASCII content keeps the body's byte size apart from its character
  # count, so a content_size stat measured in characters fails the stats test.
  def rss_body(items: 1)
    entries = items.times.map do |i|
      <<~XML
        <item>
          <title>Test Post #{i + 1}</title>
          <description>Тестовое содержимое превью</description>
          <link>https://example.com/post#{i + 1}</link>
          <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
          <guid>https://example.com/post#{i + 1}</guid>
        </item>
      XML
    end

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <description>Test Description</description>
          <link>https://example.com</link>
          #{entries.join}
        </channel>
      </rss>
    XML
  end

  def stub_rss_loader(items: 1)
    stub_request(:get, FEED_URL)
      .to_return(status: 200, body: rss_body(items: items), headers: { "Content-Type" => "application/xml" })
  end

  test "#execute should mark the preview ready with normalized posts and ready_at" do
    stub_rss_loader

    FeedPreviewWorkflow.new(feed_preview, run_id: RUN_ID).execute

    feed_preview.reload
    assert feed_preview.ready?
    assert feed_preview.ready_at.present?
    assert_equal 1, feed_preview.posts_count
    assert_equal "https://example.com/post1", feed_preview.posts_data.first["source_url"]
  end

  test "#execute should include normalized comments in preview posts" do
    url = "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc123def456ghi789jkl"
    preview = create(:feed_preview, user: user, feed_profile_key: "youtube",
                     params: { "url" => url, "include_description" => true },
                     status: :pending, run_id: RUN_ID)
    stub_request(:get, url).to_return(
      status: 200,
      body: file_fixture("feeds/youtube/feed.xml").read,
      headers: { "Content-Type" => "application/atom+xml" }
    )

    FeedPreviewWorkflow.new(preview, run_id: RUN_ID).execute

    comments = preview.reload.posts_data.first["comments"]
    assert_equal 1, comments.size
    assert_includes comments.first, "A beginner-friendly introduction"
  end

  test "#execute should record the stats reported to preview readers" do
    body = rss_body
    stub_request(:get, FEED_URL)
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/xml" })

    FeedPreviewWorkflow.new(feed_preview, run_id: RUN_ID).execute

    stats = feed_preview.reload.data["stats"]
    assert_equal body.bytesize, stats["content_size"]
    assert_equal 1, stats["total_entries"]
    assert_equal 1, stats["preview_entries"]
    assert_equal 1, stats["normalized_posts"]
  end

  test "#execute should cap the preview at PREVIEW_POSTS_LIMIT while reporting the full entry count" do
    total = FeedPreview::PREVIEW_POSTS_LIMIT + 2
    stub_rss_loader(items: total)

    FeedPreviewWorkflow.new(feed_preview, run_id: RUN_ID).execute

    feed_preview.reload
    assert_equal FeedPreview::PREVIEW_POSTS_LIMIT, feed_preview.posts_count
    assert_equal total, feed_preview.total_entries_count
  end

  test "#execute should mark the preview failed and re-raise when a step fails" do
    stub_request(:get, FEED_URL).to_return(status: 500, body: "")

    assert_raises(Loader::Error) do
      FeedPreviewWorkflow.new(feed_preview, run_id: RUN_ID).execute
    end

    assert feed_preview.reload.failed?
  end

  test "#execute should halt before loading when the run is superseded" do
    preview = create(:feed_preview, user: user, feed_profile_key: "rss",
                     params: { "url" => "https://example.com/superseded.xml" },
                     status: :pending, run_id: NEXT_RUN_ID)

    # No loader stub: a request would raise WebMock::NetConnectNotAllowedError.
    FeedPreviewWorkflow.new(preview, run_id: RUN_ID).execute

    preview.reload
    assert preview.pending?, "expected preview to remain pending (not failed), got #{preview.status}"
    assert_nil preview.data
  end

  test "#execute should run the AI loader with the preview's selected model for the preview purpose" do
    credential = create(:ai_credential, :active, user: user, available_models: [{ "id" => "claude-sonnet-4-6" }])
    preview = create(:feed_preview, user: user, feed_profile_key: "llm",
                     params: { "prompt" => "rust async" }, ai_credential: credential,
                     ai_model: "claude-sonnet-4-6", status: :pending, run_id: AI_RUN_ID)

    captured_feed = nil
    captured_context = nil
    fake_client = Class.new do
      attr_reader :credential

      def initialize(credential, callback)
        @credential = credential
        @callback = callback
      end

      def call(context, **_options)
        @callback.call(context)
        LlmClient::Result.new(payload: { "items" => [] }, usage_id: 1)
      end
    end

    LlmClient.stub(:for, lambda { |feed|
      captured_feed = feed
      fake_client.new(credential, ->(context) { captured_context = context })
    }) do
      FeedPreviewWorkflow.new(preview, run_id: AI_RUN_ID).execute
    end

    assert_equal credential.id, captured_feed.ai_credential_id
    assert_equal "claude-sonnet-4-6", captured_context.model
    assert_equal :preview, captured_context.purpose
  end
end
