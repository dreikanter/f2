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
    assert_equal 3, metric.reload.posts_count
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

    stub_feed
    stub_comic("broken")
    FeedRefreshWorkflow.new(feed).execute

    assert_equal 1, metric.reload.posts_count
    assert_equal 1, metric.invalid_posts_count
  end

  test "#execute should count posts published while later entries normalize" do
    stub_feed("first", "last")
    stub_comic("first")
    stub_request(:get, page_url("last")).to_return do
      feed.posts.find_by!(uid: "first").update!(status: :published, reposted_at: Time.current)
      { body: '<div id="comic"><img src="https://example.com/last.png"></div>' }
    end

    FeedRefreshWorkflow.new(feed).execute

    assert feed.posts.find_by!(uid: "first").published?
    event = feed.events.where(type: "feed_refresh").sole
    assert_equal 2, event.metadata.dig("stats", "new_posts")
    assert_equal 2, feed.feed_metrics.sole.posts_count
  end

  test "#execute should roll back the entry and post when recording its metrics fails" do
    stub_feed("available")
    stub_comic("available")

    FeedMetric.stub(:record, ->(**) { raise ActiveRecord::StatementInvalid, "metrics failed" }) do
      assert_raises(ActiveRecord::StatementInvalid) { FeedRefreshWorkflow.new(feed).execute }
    end

    assert_empty feed.posts
    assert feed.feed_entries.sole.pending?
    assert_equal 0, feed.reload.imported_posts_count
    assert_empty feed.feed_metrics
    event = feed.events.where(type: "feed_refresh").sole
    assert_equal "failed", event.metadata["status"]
    assert_equal "metrics failed", event.metadata.dig("error", "message")
    assert_empty event.references

    FeedRefreshWorkflow.new(feed).execute

    assert feed.posts.sole.enqueued?
    assert feed.feed_entries.sole.processed?
    assert_equal 1, feed.feed_metrics.sole.posts_count
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
