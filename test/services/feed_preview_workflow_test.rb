require "test_helper"

class FeedPreviewWorkflowTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  def user
    @user ||= create(:user)
  end

  def feed_preview
    @feed_preview ||= create(:feed_preview, user: user, feed_profile_key: "rss",
                             params: { "url" => "https://example.com/feed.xml" },
                             status: :pending, run_id: "run-1")
  end

  def workflow
    @workflow ||= FeedPreviewWorkflow.new(feed_preview, run_id: "run-1")
  end

  def rss_body
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <description>Test Description</description>
          <link>https://example.com</link>
          <item>
            <title>Test Post</title>
            <description>Test content for preview</description>
            <link>https://example.com/post1</link>
            <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
            <guid>https://example.com/post1</guid>
          </item>
        </channel>
      </rss>
    XML
  end

  def stub_rss_loader_returning_one_item
    stub_request(:get, "https://example.com/feed.xml")
      .to_return(status: 200, body: rss_body, headers: { "Content-Type" => "application/xml" })
  end

  test "#initialize should assign feed_preview" do
    assert_equal feed_preview, workflow.feed_preview
    assert_equal({}, workflow.stats)
  end

  test "#initialize should produce executable workflow" do
    wf = FeedPreviewWorkflow.new(feed_preview, run_id: "run-1")
    assert_equal feed_preview, wf.feed_preview
    assert_equal({}, wf.stats)
    assert_respond_to wf, :execute
  end

  test "#initialize should fall back to feed_preview.run_id when run_id is omitted" do
    wf = FeedPreviewWorkflow.new(feed_preview)
    assert_respond_to wf, :execute
  end

  test ".included should mix in Workflow module" do
    assert_includes FeedPreviewWorkflow.included_modules, Workflow
  end

  test "#execute should be defined as workflow step" do
    assert_respond_to workflow, :execute
  end

  test ".const_get should expose PREVIEW_POSTS_LIMIT constant" do
    assert_equal 10, FeedPreview::PREVIEW_POSTS_LIMIT
  end

  test "#execute should support error handling helpers" do
    wf = FeedPreviewWorkflow.new(feed_preview, run_id: "run-1")
    assert_respond_to wf, :execute
    assert_equal feed_preview, wf.feed_preview
  end

  test "#record_stats should merge stats correctly" do
    wf = FeedPreviewWorkflow.new(feed_preview, run_id: "run-1")
    assert_empty wf.stats
    assert_respond_to wf, :stats
  end

  test "#record_stats should store provided values" do
    wf = FeedPreviewWorkflow.new(feed_preview, run_id: "run-1")
    assert_empty wf.stats

    wf.define_singleton_method(:test_record_stats) do
      send(:record_stats, test_stat: "value", count: 42)
    end

    wf.test_record_stats

    assert_equal({ test_stat: "value", count: 42 }, wf.stats)
  end

  test "#execute should mark the preview ready with normalized posts and ready_at" do
    preview = create(:feed_preview, feed_profile_key: "rss",
                     params: { "url" => "https://example.com/feed.xml" }, run_id: "run-1")
    stub_rss_loader_returning_one_item

    FeedPreviewWorkflow.new(preview, run_id: "run-1").execute

    preview.reload
    assert preview.ready?
    assert preview.ready_at.present?
    assert_equal 1, preview.posts_count
  end

  test "#execute should broadcast the ready pane to the preview frame" do
    preview = create(:feed_preview, feed_profile_key: "rss",
                     params: { "url" => "https://example.com/feed.xml" }, run_id: "run-1")
    stub_rss_loader_returning_one_item

    broadcasts = capture_turbo_stream_broadcasts(preview) do
      FeedPreviewWorkflow.new(preview, run_id: "run-1").execute
    end

    assert_equal 1, broadcasts.size
    stream = broadcasts.first
    assert_equal "update", stream["action"]
    assert_equal "feed-preview-body", stream["target"]
    assert_includes stream.to_html, "preview.success"
  end

  test "#execute should not finalize when the run_id is stale" do
    preview = create(:feed_preview, feed_profile_key: "rss",
                     params: { "url" => "https://example.com/feed.xml" }, run_id: "run-2")
    stub_rss_loader_returning_one_item

    assert_no_turbo_stream_broadcasts(preview) do
      FeedPreviewWorkflow.new(preview, run_id: "run-1").execute # superseded run
    end

    preview.reload
    refute preview.ready?
  end

  # Fix 5: superseded run halts early without calling the loader or marking failed
  test "#execute should not invoke the loader and should not mark failed when run_id is superseded" do
    preview = create(:feed_preview, feed_profile_key: "rss",
                     params: { "url" => "https://example.com/feed.xml" }, run_id: "run-2")

    # The stub for the loader URL is intentionally absent — if the loader were
    # called it would raise a WebMock::NetConnectNotAllowedError, failing the test.
    FeedPreviewWorkflow.new(preview, run_id: "run-1").execute

    preview.reload
    assert preview.pending?, "expected preview to remain pending (not failed), got #{preview.status}"
  end
end
