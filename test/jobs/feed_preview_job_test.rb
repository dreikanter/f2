require "test_helper"

class FeedPreviewJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  def feed_profile
    @feed_profile ||= create(:feed_profile, user: user)
  end

  def feed_preview
    @feed_preview ||= create(:feed_preview, user: user, feed_profile: feed_profile)
  end

  test "should be queued on default queue" do
    assert_equal "default", FeedPreviewJob.queue_name
  end

  test "should execute FeedPreviewWorkflow for valid preview" do
    workflow_mock = mock
    workflow_mock.expects(:execute).once

    FeedPreviewWorkflow.expects(:new).with(feed_preview).returns(workflow_mock)

    FeedPreviewJob.perform_now(feed_preview.id)
  end

  test "should handle missing feed preview gracefully" do
    # Should not raise an error
    assert_nothing_raised do
      FeedPreviewJob.perform_now("non-existent-id")
    end
  end

  test "should update preview status to failed on error" do
    workflow_mock = mock
    workflow_mock.expects(:execute).raises(StandardError.new("Test error"))

    FeedPreviewWorkflow.expects(:new).with(feed_preview).returns(workflow_mock)

    # Should re-raise the error after updating status
    assert_raises(StandardError) do
      FeedPreviewJob.perform_now(feed_preview.id)
    end

    feed_preview.reload
    assert feed_preview.failed?
  end

  test "should log error when workflow fails" do
    workflow_mock = mock
    workflow_mock.expects(:execute).raises(StandardError.new("Test error"))

    FeedPreviewWorkflow.expects(:new).with(feed_preview).returns(workflow_mock)

    Rails.logger.expects(:error).with("FeedPreviewJob failed for preview #{feed_preview.id}: Test error")

    assert_raises(StandardError) do
      FeedPreviewJob.perform_now(feed_preview.id)
    end
  end

  test "should handle error when feed preview is nil during error handling" do
    workflow_mock = mock
    workflow_mock.expects(:execute).raises(StandardError.new("Test error"))

    FeedPreviewWorkflow.expects(:new).with(feed_preview).returns(workflow_mock)

    # Simulate the preview being deleted during execution
    FeedPreview.any_instance.expects(:update!).raises(ActiveRecord::RecordNotFound)

    assert_raises(StandardError) do
      FeedPreviewJob.perform_now(feed_preview.id)
    end
  end

  test "should perform job later" do
    assert_enqueued_with(job: FeedPreviewJob, args: [feed_preview.id]) do
      FeedPreviewJob.perform_later(feed_preview.id)
    end
  end
end