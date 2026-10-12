require "test_helper"

class FeedRefreshWorkflowRecoveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def feed
    @feed ||= create(:feed, :enabled, feed_profile_key: "buni")
  end

  def page_url(uid)
    "https://example.com/#{uid}"
  end

  def stub_feed(*uids)
    items = uids.each_with_index.map do |uid, index|
      <<~XML
        <item>
          <guid>#{uid}</guid><title>#{uid}</title><link>#{page_url(uid)}</link>
          <pubDate>#{(2.hours.ago + index.minutes).rfc822}</pubDate>
        </item>
      XML
    end.join

    stub_request(:get, feed.url).to_return(body: <<~RSS)
      <rss version="2.0"><channel><title>Comics</title>#{items}</channel></rss>
    RSS
  end

  def stub_comic(uid)
    stub_request(:get, page_url(uid)).to_return(body: <<~HTML)
      <div id="comic"><img src="https://example.com/#{uid}.png" alt="#{uid}"></div>
    HTML
  end

  test "#execute should continue the batch and retry a pending entry outside the next source response" do
    stub_feed("unavailable", "available")
    stub_request(:get, page_url("unavailable")).to_raise(Faraday::ConnectionFailed.new("connection refused"))
    stub_comic("available")

    assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
      FeedRefreshWorkflow.new(feed).execute
    end

    assert_equal ["available"], feed.posts.pluck(:uid)
    assert_equal ["unavailable"], feed.feed_entries.pending.pluck(:uid)
    assert_equal 2, FeedEntryUid.where(feed: feed).count
    first_event = feed.events.where(type: "feed_refresh").sole
    assert_equal 1, first_event.metadata.dig("stats", "deferred_entries")
    assert_equal "deferred", first_event.details.sole.dig("stats", "outcome")

    stub_feed
    stub_comic("unavailable")

    assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
      FeedRefreshWorkflow.new(feed).execute
    end

    assert_equal %w[available unavailable], feed.posts.order(:uid).pluck(:uid)
    assert_empty feed.feed_entries.pending
    assert_equal 2, FeedEntryUid.where(feed: feed).count
    recovered_event = feed.events.where(type: "feed_refresh").order(:id).last
    assert_equal ["unavailable"], recovered_event.references.map(&:uid)
    assert_equal 1, recovered_event.metadata.dig("stats", "new_posts")

    # Existing posts may still be awaiting publication, so refresh also restarts
    # the publisher without recreating or renormalizing those posts.
    assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
      assert_empty FeedRefreshWorkflow.new(feed).execute
    end

    assert_equal 2, feed.posts.count
    assert_requested :get, page_url("available"), times: 1
    assert_requested :get, page_url("unavailable"), times: 2
  end

  test "#execute should defer required content on a server error" do
    stub_feed("unavailable")
    stub_request(:get, page_url("unavailable")).to_return(status: 503)

    assert_no_enqueued_jobs(only: PostPublishJob) do
      assert_empty FeedRefreshWorkflow.new(feed).execute
    end

    assert feed.feed_entries.sole.pending?
    assert_empty feed.posts
    event = feed.events.where(type: "feed_refresh").sole
    assert_equal "completed", event.metadata["status"]
    assert event.warning?
    assert_equal 503, event.details.sole.dig("stats", "status")
  end

  test "#execute should keep permanent rejection out of later retries" do
    stub_feed("missing")
    stub_request(:get, page_url("missing")).to_return(status: 404)

    FeedRefreshWorkflow.new(feed).execute

    assert feed.posts.sole.rejected?
    assert feed.feed_entries.sole.processed?
    assert_empty FeedRefreshWorkflow.new(feed).execute
    assert_equal 1, feed.posts.count
    assert_requested :get, page_url("missing"), times: 1
  end

  test "#execute should preserve earlier posts when another normalizer raises" do
    stub_feed("first", "broken", "last")
    stub_comic("first")
    stub_request(:get, page_url("broken")).to_raise(ArgumentError.new("unexpected failure"))
    stub_comic("last")

    assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
      assert_raises(ArgumentError) { FeedRefreshWorkflow.new(feed).execute }
    end

    assert_equal ["first"], feed.posts.pluck(:uid)
    assert_equal ["first"], feed.feed_entries.processed.pluck(:uid)
    assert_equal %w[broken last], feed.feed_entries.pending.order(:uid).pluck(:uid)
    event = feed.events.where(type: "feed_refresh").sole
    assert_equal "failed", event.metadata["status"]
    assert_equal "unexpected failure", event.metadata.dig("error", "message")
    assert_equal [feed.posts.sole], event.references
    assert_equal 1, event.metadata.dig("stats", "new_posts")
    assert_equal 1, feed.reload.imported_posts_count
    metric = FeedMetric.find_by!(feed: feed, date: Date.current)
    assert_equal 1, metric.posts_count
    assert_equal 0, metric.invalid_posts_count

    stub_feed
    stub_comic("broken")
    FeedRefreshWorkflow.new(feed).execute

    assert_equal %w[broken first last], feed.posts.order(:uid).pluck(:uid)
    assert_empty feed.feed_entries.pending
    assert_equal 3, feed.reload.imported_posts_count
    assert_requested :get, page_url("first"), times: 1
    assert_requested :get, page_url("broken"), times: 2
    assert_requested :get, page_url("last"), times: 1
  end

  test "#execute should count rejected posts saved before another normalizer fails" do
    stub_feed("missing", "broken")
    stub_request(:get, page_url("missing")).to_return(status: 404)
    stub_request(:get, page_url("broken")).to_raise(ArgumentError.new("unexpected failure"))

    assert_raises(ArgumentError) { FeedRefreshWorkflow.new(feed).execute }

    metric = FeedMetric.find_by!(feed: feed, date: Date.current)
    assert_equal 0, metric.posts_count
    assert_equal 1, metric.invalid_posts_count
    assert feed.posts.sole.rejected?
  end

  test "#execute should still persist rejected posts with an invalid source URL" do
    feed.update!(feed_profile_key: "rss")
    stub_request(:get, feed.url).to_return(body: <<~RSS)
      <rss version="2.0"><channel><title>Articles</title>
        <item><guid>invalid-url</guid><title>Article without a link</title></item>
      </channel></rss>
    RSS

    FeedRefreshWorkflow.new(feed).execute

    assert feed.posts.sole.rejected?
    assert_includes feed.posts.sole.validation_errors, "missing_url"
    assert feed.feed_entries.sole.processed?
  end
end
