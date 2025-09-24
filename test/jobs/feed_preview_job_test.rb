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
    # Create a preview with a valid URL and stub the network request
    valid_preview = create(:feed_preview, user: user, feed_profile: feed_profile, url: "http://example.com/feed.xml")

    # Stub the HTTP request to avoid actual network calls with proper RSS format
    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <description>Test Description</description>
          <link>http://example.com</link>
          <item>
            <title>Test Post</title>
            <description>Test content that is longer than the minimum required</description>
            <link>http://example.com/post1</link>
            <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
            <guid>http://example.com/post1</guid>
          </item>
        </channel>
      </rss>
    XML

    stub_request(:get, "http://example.com/feed.xml")
      .to_return(status: 200, body: rss_content, headers: { "Content-Type" => "application/xml" })

    # This should execute the workflow path (line 9)
    assert_nothing_raised do
      FeedPreviewJob.perform_now(valid_preview.id)
    end

    # Verify the preview was processed successfully
    valid_preview.reload
    assert valid_preview.ready?
  end

  test "should handle workflow errors and update preview status" do
    # Create a preview with URL that will pass validation but fail in processing
    failing_preview = create(:feed_preview,
                            user: user,
                            feed_profile: feed_profile,
                            url: "http://example.com/will-fail.xml",
                            status: :processing)

    # Stub the request to return malformed content that will cause processing to fail
    stub_request(:get, "http://example.com/will-fail.xml")
      .to_return(status: 500, body: "Server Error")

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
                            url: "http://example.com/error.xml")

    # Stub the request to cause an error
    stub_request(:get, "http://example.com/error.xml")
      .to_raise(StandardError.new("Network error"))

    # This should trigger the error logging path
    assert_raises StandardError do
      FeedPreviewJob.perform_now(failing_preview.id)
    end
  end
end
