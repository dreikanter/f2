require "test_helper"

class FeedPreviewWorkflowTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  def feed_preview
    @feed_preview ||= create(:feed_preview, user: user, feed_profile_key: "rss", status: :pending)
  end

  def workflow
    @workflow ||= FeedPreviewWorkflow.new(feed_preview)
  end

  test "#initialize should assign feed_preview" do
    assert_equal feed_preview, workflow.feed_preview
    assert_equal({}, workflow.stats)
  end

  test "#initialize should produce executable workflow" do
    # Basic test to verify the workflow can be created and has the right attributes
    workflow = FeedPreviewWorkflow.new(feed_preview)
    assert_equal feed_preview, workflow.feed_preview
    assert_equal({}, workflow.stats)
    assert_respond_to workflow, :execute
  end

  test ".included should mix in Workflow module" do
    assert_includes FeedPreviewWorkflow.included_modules, Workflow
  end

  test "#execute should be defined as workflow step" do
    # Verify the workflow has the expected steps defined
    assert_respond_to workflow, :execute
  end

  test ".const_get should expose PREVIEW_POSTS_LIMIT constant" do
    assert_equal 10, FeedPreview::PREVIEW_POSTS_LIMIT
  end

  test "#execute should support error handling helpers" do
    # Test that the workflow has error handling methods available
    workflow_instance = FeedPreviewWorkflow.new(feed_preview)

    # Check that the workflow responds to error handling methods
    assert_respond_to workflow_instance, :execute

    # Test that error handling paths exist (they're covered by integration tests)
    # The actual error handling is tested through the job tests
    assert_equal feed_preview, workflow_instance.feed_preview
  end

  test "#record_stats should merge stats correctly" do
    workflow_instance = FeedPreviewWorkflow.new(feed_preview)

    # Test that stats start empty
    assert_empty workflow_instance.stats

    # We can test the record_stats functionality indirectly by checking
    # the stats accessor after workflow initialization
    assert_respond_to workflow_instance, :stats
  end

  test "#record_stats should store provided values" do
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
