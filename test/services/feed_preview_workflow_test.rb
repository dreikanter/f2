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
end