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

  test "should initialize workflow successfully" do
    # Basic test to verify the workflow can be created and has the right attributes
    workflow = FeedPreviewWorkflow.new(feed_preview)
    assert_equal feed_preview, workflow.feed_preview
    assert_equal({}, workflow.stats)
    assert_respond_to workflow, :execute
  end

  test "should include Workflow module" do
    assert_includes FeedPreviewWorkflow.included_modules, Workflow
  end

  test "should have defined steps" do
    # Verify the workflow has the expected steps defined
    assert_respond_to workflow, :execute
  end

  test "should have PREVIEW_POSTS_LIMIT constant available" do
    assert_equal 10, FeedPreview::PREVIEW_POSTS_LIMIT
  end

  test "should handle workflow execution with errors by updating preview status" do
    # Create a workflow that will fail due to network error
    failing_preview = create(:feed_preview,
                            user: user,
                            feed_profile: feed_profile,
                            url: "http://example.com/will-fail.xml",
                            status: :pending)

    # Stub the request to cause an error
    stub_request(:get, "http://example.com/will-fail.xml")
      .to_raise(StandardError.new("Network error"))

    workflow_instance = FeedPreviewWorkflow.new(failing_preview)

    # Execute should not raise, but should handle error internally
    assert_nothing_raised do
      workflow_instance.execute
    end

    # Check that the feed preview status was updated to failed
    failing_preview.reload
    assert failing_preview.failed?
  end

  test "should merge stats correctly" do
    workflow_instance = FeedPreviewWorkflow.new(feed_preview)

    # Test that stats start empty
    assert_empty workflow_instance.stats

    # We can test the record_stats functionality indirectly by checking
    # the stats accessor after workflow initialization
    assert_respond_to workflow_instance, :stats
  end

  test "should call record_stats method" do
    # Test the private record_stats method functionality
    workflow_instance = FeedPreviewWorkflow.new(feed_preview)

    # We can't call private methods directly, but we can verify the stats accessor works
    assert_empty workflow_instance.stats

    # Simulate stats recording through method stubbing
    workflow_instance.define_singleton_method(:test_record_stats) do
      send(:record_stats, test_stat: "value", count: 42)
    end

    workflow_instance.test_record_stats

    expected_stats = { test_stat: "value", count: 42 }
    assert_equal expected_stats, workflow_instance.stats
  end
end
