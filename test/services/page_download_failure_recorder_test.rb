require "test_helper"

class PageDownloadFailureRecorderTest < ActiveSupport::TestCase
  test "#call should create separate warnings without changing the parent metadata" do
    feed = create(:feed)
    event = create(:event, type: "feed_refresh", subject: feed, user: feed.user)
    metadata = event.metadata.deep_dup
    recorder = PageDownloadFailureRecorder.new(event: event, context: { uid: "entry-1" })
    error = PageFetcher::Error.new(url: "https://example.com/article", status: 503)

    2.times { recorder.call(error) }

    assert_equal metadata, event.reload.metadata
    assert_equal 2, event.references.size
    event.references.each do |failure|
      assert failure.warning?
      assert_equal "page_download_failed", failure.type
      assert_equal feed, failure.subject
      assert_equal feed.user, failure.user
      assert_equal "entry-1", failure.metadata.dig("stats", "uid")
      assert_equal 503, failure.metadata.dig("stats", "status")
    end
  end
end
