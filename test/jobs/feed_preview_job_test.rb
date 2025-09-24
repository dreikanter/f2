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
end