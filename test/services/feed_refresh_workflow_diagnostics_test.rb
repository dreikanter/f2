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

  test "#execute should record diagnostics from a normalizer without page fetching" do
    stub_feed

    feed.stub(:normalizer_class, WarningNormalizer) { FeedRefreshWorkflow.new(feed).execute }

    assert feed.posts.sole.enqueued?
    event = feed.events.where(type: "feed_refresh").sole
    assert event.warning?
    assert_equal 1, event.metadata.dig("stats", "normalization_warnings")
    assert_equal "Entry date was inferred", event.details.sole["message"]
    assert_equal "entry-1", event.details.sole.dig("stats", "uid")
    assert_equal "fallback", event.details.sole.dig("stats", "outcome")
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
    assert_equal "Entry date was inferred", event.details.sole["message"]
    assert_equal "failed", event.details.sole.dig("stats", "outcome")
  end

  test "#execute should preserve errors raised while constructing the normalizer" do
    stub_feed

    feed.stub(:normalizer_instance, ->(_) { raise "initialization failed" }) do
      error = assert_raises(RuntimeError) { FeedRefreshWorkflow.new(feed).execute }
      assert_equal "initialization failed", error.message
    end
  end
end
