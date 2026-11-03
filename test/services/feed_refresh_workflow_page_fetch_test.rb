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

  test "#execute should retain a deferred entry's page failure in the completed event" do
    stub_feed
    stub_request(:get, PAGE_URL).to_raise(Faraday::TimeoutError)

    reports = capture_error_reports { FeedRefreshWorkflow.new(feed).execute }

    assert_empty reports
    assert_empty feed.posts
    assert feed.feed_entries.sole.pending?
    event = feed.events.where(type: "feed_refresh").sole
    assert_equal "completed", event.metadata["status"]
    assert event.warning?
    assert_empty event.details
    attempt = event.referenced_events.sole
    detail = attempt.metadata.dig("stats", "diagnostics").sole.fetch("details")
    assert_equal "comic-1", detail["uid"]
    assert_equal PAGE_URL, detail["url"]
    assert_equal "HttpClient::TimeoutError", detail["error_class"]
    assert_equal "deferred", attempt.metadata.dig("stats", "outcome")
  end

  test "#execute should retain a rejected post's page failure in the completed event" do
    stub_feed
    stub_request(:get, PAGE_URL).to_return(status: 404)

    reports = capture_error_reports { FeedRefreshWorkflow.new(feed).execute }

    assert_empty reports
    assert feed.posts.sole.rejected?
    event = feed.events.where(type: "feed_refresh").sole
    assert_equal "completed", event.metadata["status"]
    assert event.warning?
    assert_empty event.details
    attempt = event.referenced_events.sole
    detail = attempt.metadata.dig("stats", "diagnostics").sole.fetch("details")
    assert_equal "comic-1", detail["uid"]
    assert_equal PAGE_URL, detail["url"]
    assert_equal 404, detail["status"]
    assert_equal "rejected", attempt.metadata.dig("stats", "outcome")
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
    assert event.warning?
    assert_equal 503, event.referenced_events.sole.metadata.dig("stats", "diagnostics").sole.dig("details", "status")
    assert_equal "imported", event.referenced_events.sole.metadata.dig("stats", "outcome")
    assert_equal [feed.posts.sole], event.references.grep(Post)
  end

  test "#execute should preserve page diagnostics when the refresh later fails" do
    feed.update!(feed_profile_key: "smbc")
    stub_feed
    stub_request(:get, PAGE_URL).to_return(status: 503)

    feed.stub(:refresh_post_stats!, -> { raise ActiveRecord::StatementInvalid, "write failed" }) do
      assert_raises(ActiveRecord::StatementInvalid) { FeedRefreshWorkflow.new(feed).execute }
    end

    event = feed.events.where(type: "feed_refresh").sole
    assert_equal "failed", event.metadata["status"]
    assert_equal "write failed", event.metadata.dig("error", "message")
    assert_equal 503, event.referenced_events.sole.metadata.dig("stats", "diagnostics").sole.dig("details", "status")
    assert_empty feed.posts
    assert feed.feed_entries.sole.pending?
    assert_empty event.references.grep(Post)
  end
end
