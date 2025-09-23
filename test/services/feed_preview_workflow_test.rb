require "test_helper"

class FeedPreviewWorkflowTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed_profile
    @feed_profile ||= create(:feed_profile, user: user, loader: "http", processor: "rss", normalizer: "rss")
  end

  def feed_preview
    @feed_preview ||= create(:feed_preview, feed_profile: feed_profile)
  end

  test "initializes workflow with feed preview and stats" do
    workflow = FeedPreviewWorkflow.new(feed_preview)

    assert_equal feed_preview, workflow.feed_preview
    assert_equal({}, workflow.stats)
  end

  test "workflow has correct step sequence defined" do
    expected_steps = [
      :initialize_workflow,
      :load_feed_contents,
      :process_feed_contents,
      :normalize_entries,
      :finalize_workflow
    ]

    assert_equal expected_steps, FeedPreviewWorkflow.workflow_steps
  end

  test "provides access to timing information" do
    workflow = FeedPreviewWorkflow.new(feed_preview)

    assert_equal({}, workflow.step_durations)
    assert_equal 0.0, workflow.total_duration
    assert_nil workflow.current_step
  end

  test "executes complete workflow with real RSS data and creates preview" do
    preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")

    workflow = FeedPreviewWorkflow.new(preview)

    # Create real RSS content
    sample_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <description>Test RSS Feed</description>
          <item>
            <guid>entry-123</guid>
            <title>First Test Entry</title>
            <description>This is a test entry description</description>
            <link>https://example.com/entry-123</link>
            <pubDate>#{1.hour.ago.rfc822}</pubDate>
          </item>
          <item>
            <guid>entry-456</guid>
            <title>Second Test Entry</title>
            <description>Another test entry</description>
            <link>https://example.com/entry-456</link>
            <pubDate>#{2.hours.ago.rfc822}</pubDate>
          </item>
        </channel>
      </rss>
    RSS

    # Use real HTTP loader with stubbed network call
    WebMock.stub_request(:get, preview.url).to_return(body: sample_rss, status: 200)

    result = workflow.execute

    # Verify workflow completed successfully
    assert_equal 2, result.length, "Should return 2 posts"

    # Verify posts data structure
    first_post = result.first
    assert first_post["content"].include?("test entry description")
    assert_equal "https://example.com/entry-123", first_post["source_url"]
    assert_equal "entry-123", first_post["uid"]
    assert first_post["published_at"].present?
    assert first_post["attachments"].is_a?(Array)

    # Verify preview was updated
    preview.reload
    assert_equal "completed", preview.status
    assert preview.data.present?
    assert_equal 2, preview.posts_count

    # Verify workflow stats were recorded
    assert workflow.stats[:started_at]
    assert workflow.stats[:content_size] > 0
    assert_equal 2, workflow.stats[:total_entries]
    assert_equal 2, workflow.stats[:preview_entries]
    assert_equal 2, workflow.stats[:normalized_posts]
    assert workflow.stats[:completed_at]
    assert workflow.stats[:total_duration] >= 0
  end

  test "limits entries to PREVIEW_LIMIT" do
    preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")

    # Create RSS with more than the limit
    items = 15.times.map do |i|
      <<~ITEM
        <item>
          <guid>entry-#{i}</guid>
          <title>Entry #{i}</title>
          <description>Description #{i}</description>
          <link>https://example.com/entry-#{i}</link>
          <pubDate>#{i.hours.ago.rfc822}</pubDate>
        </item>
      ITEM
    end

    large_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Large Feed</title>
          #{items.join}
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, preview.url).to_return(body: large_rss, status: 200)

    workflow = FeedPreviewWorkflow.new(preview)
    result = workflow.execute

    # Should only process the preview limit
    assert_equal FeedPreview::PREVIEW_LIMIT, result.length
    assert_equal 15, workflow.stats[:total_entries]
    assert_equal FeedPreview::PREVIEW_LIMIT, workflow.stats[:preview_entries]
    assert_equal FeedPreview::PREVIEW_LIMIT, workflow.stats[:normalized_posts]
  end

  test "handles HTTP loading errors gracefully" do
    preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")

    workflow = FeedPreviewWorkflow.new(preview)

    # Stub network request to timeout
    WebMock.stub_request(:get, preview.url).to_timeout

    error = assert_raises(StandardError) do
      workflow.execute
    end

    assert_match(/execution expired/, error.message)

    # Verify error handling
    preview.reload
    assert_equal "failed", preview.status
    assert workflow.stats[:started_at]
    assert_equal :load_feed_contents, workflow.stats[:failed_at_step]
  end

  test "handles RSS processing errors gracefully" do
    preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")

    workflow = FeedPreviewWorkflow.new(preview)

    # Return invalid RSS that will cause parsing errors
    invalid_rss = "<invalid>not valid RSS</malformed>"

    WebMock.stub_request(:get, preview.url).to_return(body: invalid_rss, status: 200)

    # RSS processor returns empty array for invalid RSS, so workflow should complete
    result = workflow.execute

    # Should complete with no posts due to invalid RSS
    assert_equal 0, result.length

    preview.reload
    assert_equal "completed", preview.status
    assert_equal 0, preview.posts_count

    # Verify stats show no entries processed
    assert workflow.stats[:started_at]
    assert workflow.stats[:total_entries] == 0 || workflow.stats[:total_entries].nil?
    assert workflow.stats[:completed_at]
  end

  test "handles empty feed content gracefully" do
    preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")

    workflow = FeedPreviewWorkflow.new(preview)

    # Empty RSS with no items
    empty_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Empty Feed</title>
          <description>No items</description>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, preview.url).to_return(body: empty_rss, status: 200)

    result = workflow.execute

    # Should complete successfully with no posts
    assert_equal 0, result.length

    preview.reload
    assert_equal "completed", preview.status
    assert_equal 0, preview.posts_count

    # Verify stats show empty processing
    assert workflow.stats[:total_entries] == 0 || workflow.stats[:total_entries].nil?
    assert workflow.stats[:preview_entries] == 0 || workflow.stats[:preview_entries].nil?
    assert workflow.stats[:normalized_posts] == 0 || workflow.stats[:normalized_posts].nil?
  end

  test "creates temporary feed object with correct methods" do
    preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")
    workflow = FeedPreviewWorkflow.new(preview)

    # Mock the workflow steps to inspect the temp feed
    temp_feed = nil
    workflow.define_singleton_method(:load_feed_contents) do |tf|
      temp_feed = tf
      { temp_feed: tf, raw_data: "<rss></rss>" }
    end

    workflow.define_singleton_method(:process_feed_contents) { |input| { temp_feed: input[:temp_feed], entries: [] } }
    workflow.define_singleton_method(:normalize_entries) { |input| [] }
    workflow.define_singleton_method(:finalize_workflow) { |posts| posts }

    begin
      workflow.execute
    rescue
      # We just want to capture the temp_feed
    end

    assert temp_feed.present?
    assert_equal preview.url, temp_feed.url
    assert_equal preview.feed_profile, temp_feed.feed_profile
    assert temp_feed.respond_to?(:loader_instance)
    assert temp_feed.respond_to?(:processor_instance)
    assert temp_feed.respond_to?(:normalizer_instance)
  end

  test "updates preview status during workflow execution" do
    preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml", status: :pending)

    # Mock a simple successful workflow
    WebMock.stub_request(:get, preview.url).to_return(body: "<rss><channel></channel></rss>", status: 200)

    workflow = FeedPreviewWorkflow.new(preview)
    workflow.execute

    preview.reload
    assert_equal "completed", preview.status
  end

  test "handles normalization errors gracefully" do
    preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")

    # Valid RSS that will create entries
    sample_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>test-entry</guid>
            <title>Test Entry</title>
            <description>Test description</description>
          </item>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, preview.url).to_return(body: sample_rss, status: 200)

    # Override normalizer_class to cause an error
    preview.feed_profile.define_singleton_method(:normalizer_class) do
      Class.new do
        def initialize(feed_entry)
          raise StandardError, "Normalization failed"
        end
      end
    end

    workflow = FeedPreviewWorkflow.new(preview)

    error = assert_raises(StandardError) do
      workflow.execute
    end

    assert_equal "Normalization failed", error.message

    # Should fail during normalize step
    preview.reload
    assert_equal "failed", preview.status
    assert_equal :normalize_entries, workflow.stats[:failed_at_step]
  end
end
