require "test_helper"

class FeedDetailsJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  test "should be queued on default queue" do
    assert_equal "default", FeedDetailsJob.queue_name
  end

  test "should inherit from ApplicationJob" do
    assert_equal ApplicationJob, FeedDetailsJob.superclass
  end

  test "should call FeedDetails service with correct parameters" do
    url = "http://example.com/feed.xml"

    # Mock the service
    mock_service = Minitest::Mock.new
    mock_service.expect(:identify, nil)

    FeedDetails.stub(:new, ->(user:, url:) {
      assert_equal @user, user
      assert_equal "http://example.com/feed.xml", url
      mock_service
    }) do
      FeedDetailsJob.perform_now(user.id, url)
    end

    mock_service.verify
  end

  test "should handle missing user gracefully" do
    non_existent_user_id = 999999
    url = "http://example.com/feed.xml"

    # Should not raise an error or call the service
    assert_nothing_raised do
      FeedDetailsJob.perform_now(non_existent_user_id, url)
    end
  end

  test "should log warning when user not found" do
    non_existent_user_id = 999999
    url = "http://example.com/feed.xml"

    # Capture log output
    log_output = StringIO.new
    old_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log_output)

    FeedDetailsJob.perform_now(non_existent_user_id, url)

    Rails.logger = old_logger

    log_output.rewind
    log_message = log_output.read
    assert_includes log_message, "FeedDetailsJob skipped"
    assert_includes log_message, "User #{non_existent_user_id} not found"
  end
end
