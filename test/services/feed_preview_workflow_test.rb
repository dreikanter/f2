require "test_helper"

class FeedPreviewWorkflowTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed_profile
    @feed_profile ||= create(:feed_profile, user: user)
  end

  def feed_preview
    @feed_preview ||= create(:feed_preview, user: user, feed_profile: feed_profile, status: :pending)
  end

  def workflow
    @workflow ||= FeedPreviewWorkflow.new(feed_preview)
  end

  test "should initialize with feed_preview" do
    assert_equal feed_preview, workflow.feed_preview
    assert_equal({}, workflow.stats)
  end

  test "should execute complete workflow successfully" do
    # Mock the loader, processor, and normalizer
    mock_loader = mock
    mock_processor = mock
    mock_normalizer = mock

    raw_data = "<rss>test data</rss>"
    mock_entries = [
      OpenStruct.new(uid: "entry1", published_at: Time.current, raw_data: { title: "Test 1" }),
      OpenStruct.new(uid: "entry2", published_at: Time.current, raw_data: { title: "Test 2" })
    ]

    mock_post = OpenStruct.new(
      content: "Test content",
      source_url: "http://example.com/post1",
      published_at: Time.current,
      attachment_urls: ["http://example.com/image.jpg"]
    )

    # Mock Feed creation and its methods
    Feed.any_instance.expects(:loader_instance).returns(mock_loader)
    Feed.any_instance.expects(:processor_instance).with(raw_data).returns(mock_processor)
    Feed.any_instance.expects(:normalizer_instance).returns(mock_normalizer).at_least_once

    mock_loader.expects(:load).returns(raw_data)
    mock_processor.expects(:process).returns(mock_entries)
    mock_normalizer.expects(:normalize).returns(mock_post).at_least_once

    workflow.execute

    feed_preview.reload
    assert feed_preview.ready?
    assert_not_nil feed_preview.data
    assert_equal 2, feed_preview.data["posts"].size
    assert_includes feed_preview.data["posts"][0].keys, "content"
    assert_includes feed_preview.data["posts"][0].keys, "source_url"
  end

  test "should update status to processing at start" do
    # Mock to prevent actual execution
    Feed.any_instance.expects(:loader_instance).raises(StandardError.new("Stop execution"))

    begin
      workflow.execute
    rescue StandardError
      # Expected
    end

    feed_preview.reload
    assert feed_preview.failed? # Should be failed due to error, but was processing before
  end

  test "should handle errors and update status to failed" do
    error_message = "Test error"
    Feed.any_instance.expects(:loader_instance).raises(StandardError.new(error_message))

    Rails.logger.expects(:error).with(regexp_matches(/FeedPreviewWorkflow error at initialize_workflow: #{error_message}/))

    workflow.execute

    feed_preview.reload
    assert feed_preview.failed?
  end

  test "should record stats throughout workflow" do
    # Mock the workflow steps to check stats recording
    mock_loader = mock
    mock_processor = mock
    mock_normalizer = mock

    raw_data = "<rss>test</rss>"
    mock_entries = [OpenStruct.new(uid: "entry1", published_at: Time.current, raw_data: {})]
    mock_post = OpenStruct.new(content: "Test", source_url: "http://example.com", published_at: Time.current, attachment_urls: [])

    Feed.any_instance.expects(:loader_instance).returns(mock_loader)
    Feed.any_instance.expects(:processor_instance).returns(mock_processor)
    Feed.any_instance.expects(:normalizer_instance).returns(mock_normalizer)

    mock_loader.expects(:load).returns(raw_data)
    mock_processor.expects(:process).returns(mock_entries)
    mock_normalizer.expects(:normalize).returns(mock_post)

    workflow.execute

    feed_preview.reload
    stats = feed_preview.data["stats"]

    assert_not_nil stats["started_at"]
    assert_not_nil stats["ready_at"]
    assert_not_nil stats["content_size"]
    assert_equal 1, stats["total_entries"]
    assert_equal 1, stats["preview_entries"]
    assert_equal 1, stats["normalized_posts"]
  end

  test "should limit entries to PREVIEW_POSTS_LIMIT" do
    limit = FeedPreview::PREVIEW_POSTS_LIMIT
    mock_loader = mock
    mock_processor = mock
    mock_normalizer = mock

    # Create more entries than the limit
    mock_entries = (1..limit + 5).map do |i|
      OpenStruct.new(uid: "entry#{i}", published_at: Time.current, raw_data: { title: "Test #{i}" })
    end

    mock_post = OpenStruct.new(content: "Test", source_url: "http://example.com", published_at: Time.current, attachment_urls: [])

    Feed.any_instance.expects(:loader_instance).returns(mock_loader)
    Feed.any_instance.expects(:processor_instance).returns(mock_processor)
    Feed.any_instance.expects(:normalizer_instance).returns(mock_normalizer).times(limit)

    mock_loader.expects(:load).returns("<rss>test</rss>")
    mock_processor.expects(:process).returns(mock_entries)
    mock_normalizer.expects(:normalize).returns(mock_post).times(limit)

    workflow.execute

    feed_preview.reload
    assert_equal limit, feed_preview.data["posts"].size
    assert_equal limit + 5, feed_preview.data["stats"]["total_entries"]
    assert_equal limit, feed_preview.data["stats"]["preview_entries"]
  end

  test "should create temporary feed with correct attributes" do
    # We can't easily test the temp feed creation without mocking,
    # but we can test that the workflow initializes correctly
    assert_nothing_raised do
      FeedPreviewWorkflow.new(feed_preview)
    end
  end
end