require "test_helper"

class FeedRefreshWorkflowDiagnosticsTest < ActiveSupport::TestCase
  class WarningNormalizer < Normalizer::RssNormalizer
    def diagnostics
      [Normalizer::Diagnostic.new(message: "Entry date was inferred", details: { uid: feed_entry.uid })]
    end
  end

  def feed
    @feed ||= create(:feed, feed_profile_key: "rss")
  end

  def stub_feed
    stub_request(:get, feed.url).to_return(body: <<~RSS)
      <rss version="2.0"><channel><title>Entries</title><item>
        <guid>entry-1</guid><title>Entry</title><link>https://example.com/entry</link>
      </item></channel></rss>
    RSS
  end

  test "#execute should link one successful attempt to the refresh and its saved post" do
    stub_feed

    FeedRefreshWorkflow.new(feed).execute

    refresh = feed.events.where(type: "feed_refresh").sole
    attempt = refresh.referenced_events.sole
    assert_equal "entry_normalization", attempt.type
    assert attempt.info?
    assert_equal "entry-1", attempt.metadata.dig("stats", "uid")
    assert_equal "imported", attempt.metadata.dig("stats", "outcome")
    assert_empty attempt.metadata.dig("stats", "diagnostics")
    assert_equal [feed.posts.sole], attempt.references
    assert_nil refresh.metadata.dig("stats", "search_calls")
  end

  test "#execute should keep multiple diagnostics in one attempt event" do
    stub_feed
    normalizer = Class.new(WarningNormalizer) do
      def diagnostics
        super + [Normalizer::Diagnostic.new(message: "Another warning", details: { status: 503 })]
      end
    end

    feed.stub(:normalizer_class, normalizer) { FeedRefreshWorkflow.new(feed).execute }

    refresh = feed.events.where(type: "feed_refresh").sole
    attempt = refresh.referenced_events.sole
    assert attempt.warning?
    assert_equal ["Entry date was inferred", "Another warning"], attempt.metadata.dig("stats", "diagnostics").pluck("message")
    assert_equal "imported", attempt.metadata.dig("stats", "outcome")
    assert_empty refresh.details
  end

  test "#execute should record diagnostics from a normalizer without page fetching" do
    stub_feed

    feed.stub(:normalizer_class, WarningNormalizer) { FeedRefreshWorkflow.new(feed).execute }

    assert feed.posts.sole.enqueued?
    event = feed.events.where(type: "feed_refresh").sole
    assert event.warning?
    assert_empty event.details
    assert_equal "Entry date was inferred", event.referenced_events.sole.metadata.dig("stats", "diagnostics").sole.fetch("message")
    assert_equal "entry-1", event.referenced_events.sole.metadata.dig("stats", "diagnostics").sole.dig("details", "uid")
    assert_equal "imported", event.referenced_events.sole.metadata.dig("stats", "outcome")
  end

  test "#execute should retain diagnostics when normalization raises" do
    stub_feed
    broken_normalizer = Class.new(WarningNormalizer) do
      def normalize = raise "normalization failed"
    end

    feed.stub(:normalizer_class, broken_normalizer) do
      error = assert_raises(RuntimeError) { FeedRefreshWorkflow.new(feed).execute }
      assert_equal "normalization failed", error.message
    end

    event = feed.events.where(type: "feed_refresh").sole
    assert_equal "failed", event.metadata["status"]
    assert_equal "Entry date was inferred", event.referenced_events.sole.metadata.dig("stats", "diagnostics").sole.fetch("message")
    attempt = event.referenced_events.sole
    assert_equal "failed", attempt.metadata.dig("stats", "outcome")
    assert attempt.error?
    assert_equal "RuntimeError", attempt.metadata.dig("error", "class")
    assert_equal "normalization failed", attempt.message
    assert_empty attempt.references
  end

  test "#execute should defer and resume an entry without page fetching" do
    stub_feed
    deferred_normalizer = Class.new(WarningNormalizer) do
      def deferred? = true
    end

    feed.stub(:normalizer_class, deferred_normalizer) do
      assert_empty FeedRefreshWorkflow.new(feed).execute
    end

    assert_empty feed.posts
    assert feed.feed_entries.sole.pending?
    event = feed.events.where(type: "feed_refresh").sole
    assert_equal 1, event.metadata.dig("stats", "deferred_entries")
    assert_equal "deferred", event.referenced_events.sole.metadata.dig("stats", "outcome")

    feed.stub(:normalizer_class, WarningNormalizer) { FeedRefreshWorkflow.new(feed).execute }

    assert feed.posts.sole.enqueued?
    assert feed.feed_entries.sole.processed?
    attempts = feed.events.where(type: "entry_normalization").order(:id)
    assert_equal %w[deferred imported], attempts.map { |attempt| attempt.metadata.dig("stats", "outcome") }
    assert_equal 1, attempts.first.incoming_event_references.count
    assert_equal 1, attempts.last.incoming_event_references.count
  end

  test "#execute should preserve errors raised while constructing the normalizer" do
    stub_feed

    feed.stub(:normalizer_instance, ->(_) { raise "initialization failed" }) do
      error = assert_raises(RuntimeError) { FeedRefreshWorkflow.new(feed).execute }
      assert_equal "initialization failed", error.message
    end

    refresh = feed.events.where(type: "feed_refresh").sole
    attempt = refresh.referenced_events.sole
    assert attempt.error?
    assert_equal "failed", attempt.metadata.dig("stats", "outcome")
    assert_equal "entry-1", attempt.metadata.dig("stats", "uid")
    assert_equal "initialization failed", attempt.message
    assert_empty attempt.references
  end
end
