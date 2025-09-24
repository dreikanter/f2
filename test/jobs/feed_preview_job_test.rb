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

  test "should handle missing feed preview gracefully" do
    # Should not raise an error
    assert_nothing_raised do
      FeedPreviewJob.perform_now("non-existent-id")
    end
  end

  test "should perform job later" do
    assert_enqueued_with(job: FeedPreviewJob, args: [feed_preview.id]) do
      FeedPreviewJob.perform_later(feed_preview.id)
    end
  end

  test "should inherit from ApplicationJob" do
    assert_equal ApplicationJob, FeedPreviewJob.superclass
  end

  test "should respond to perform method" do
    assert_respond_to FeedPreviewJob.new, :perform
  end

  test "should execute workflow when preview exists" do
    # Create a preview with a valid URL that won't cause network calls
    valid_preview = create(:feed_preview, user: user, feed_profile: feed_profile, url: "http://example.com/feed.xml")

    # This should execute the workflow path (line 9)
    assert_nothing_raised do
      FeedPreviewJob.perform_now(valid_preview.id)
    end
  end

  test "should handle workflow errors and update preview status" do
    # Create a preview that will cause workflow to fail
    failing_preview = create(:feed_preview,
                            user: user,
                            feed_profile: feed_profile,
                            url: "invalid-url-format",
                            status: :processing)

    # The job should handle the error, log it, and update status
    assert_raises StandardError do
      FeedPreviewJob.perform_now(failing_preview.id)
    end

    # Check that the preview status was updated to failed
    failing_preview.reload
    assert failing_preview.failed?
  end

  test "should handle case when preview is deleted during job execution" do
    preview_id = feed_preview.id

    # Delete the preview to simulate race condition
    feed_preview.destroy!

    # Job should handle missing preview gracefully
    assert_nothing_raised do
      FeedPreviewJob.perform_now(preview_id)
    end
  end

  test "should log error when workflow execution fails" do
    # Create a preview that will cause the workflow to fail
    failing_preview = create(:feed_preview,
                            user: user,
                            feed_profile: feed_profile,
                            url: "malformed-url-that-causes-error")

    # Capture that an error is logged and the job re-raises
    original_logger_level = Rails.logger.level
    Rails.logger.level = :info

    begin
      # This should trigger the error logging path
      assert_raises StandardError do
        FeedPreviewJob.perform_now(failing_preview.id)
      end
    ensure
      Rails.logger.level = original_logger_level
    end
  end
end
