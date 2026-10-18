require "test_helper"

class FeedRefreshWorkflowPageFetchTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  PAGE_URL = "https://example.com/comic"

  def feed
    @feed ||= create(:feed, feed_profile_key: "buni")
  end

  def stub_feed
    stub_request(:get, feed.url).to_return(body: <<~RSS)
      <rss version="2.0"><channel><title>Comics</title>
        <item>
          <guid>comic-1</guid><title>Comic</title><link>#{PAGE_URL}</link>
          <description><![CDATA[<img src="https://example.com/comic.png">]]></description>
        </item>
      </channel></rss>
    RSS
  end

  test "#execute should record a rejected post's page failure as a separate event" do
    stub_feed
    stub_request(:get, PAGE_URL).to_raise(Faraday::TimeoutError)

    reports = capture_error_reports { FeedRefreshWorkflow.new(feed).execute }

    assert_empty reports
    assert feed.posts.sole.rejected?
    event = feed.events.where(type: "feed_refresh").sole
    assert_equal "completed", event.metadata["status"]
    assert event.info?
    assert_empty event.details
    assert_nil event.metadata.dig("stats", "search_calls")
    failure = event.references.grep(Event).sole
    assert failure.warning?
    assert_equal "page_download_failed", failure.type
    detail = failure.metadata
    assert_equal "comic-1", detail.dig("stats", "uid")
    assert_equal PAGE_URL, detail.dig("stats", "url")
    assert_equal "HttpClient::TimeoutError", detail.dig("stats", "error_class")
  end

  test "#execute should record optional page failures while enqueueing the main content" do
    feed.update!(feed_profile_key: "smbc")
    stub_feed
    stub_request(:get, PAGE_URL).to_return(status: 503)

    assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
      FeedRefreshWorkflow.new(feed).execute
    end

    assert feed.posts.sole.enqueued?
    event = feed.events.where(type: "feed_refresh").sole
    assert event.info?
    failure = event.references.grep(Event).sole
    assert_equal 503, failure.metadata.dig("stats", "status")
    assert_includes event.references, feed.posts.sole
    assert_empty event.details
  end

  test "#execute should preserve page diagnostics when the refresh later fails" do
    stub_feed
    stub_request(:get, PAGE_URL).to_return(status: 503)

    Post.stub(:insert_all, ->(*) { raise ActiveRecord::StatementInvalid, "write failed" }) do
      assert_raises(ActiveRecord::StatementInvalid) { FeedRefreshWorkflow.new(feed).execute }
    end

    event = feed.events.where(type: "feed_refresh").sole
    assert_equal "failed", event.metadata["status"]
    assert_equal "write failed", event.metadata.dig("error", "message")
    assert_equal 503, event.references.grep(Event).sole.metadata.dig("stats", "status")
  end
end
