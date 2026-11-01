require "test_helper"

class FeedRefreshWorkflowPublicationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def feed
    @feed ||= create(:feed, :enabled, feed_profile_key: "rss")
  end

  def stub_empty_feed
    stub_request(:get, feed.url).to_return(body: '<rss version="2.0"><channel><title>Empty</title></channel></rss>')
  end

  test "#execute should restart pending publication after an empty refresh" do
    entry = create(:feed_entry, feed: feed, status: :processed)
    post = create(:post, :enqueued, feed: feed, feed_entry: entry)
    stub_empty_feed

    assert_no_difference "Post.count" do
      assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
        assert_empty FeedRefreshWorkflow.new(feed).execute
      end
    end

    assert post.reload.enqueued?
  end

  test "#execute should restart pending publication without swallowing a normalization error" do
    entry = create(:feed_entry, feed: feed, status: :processed)
    post = create(:post, :enqueued, feed: feed, feed_entry: entry)
    stub_request(:get, feed.url).to_return(body: <<~RSS)
      <rss version="2.0"><channel><title>Entries</title><item>
        <guid>broken</guid><title>Broken</title><link>https://example.com/broken</link>
      </item></channel></rss>
    RSS
    broken_normalizer = Class.new(Normalizer::RssNormalizer) do
      def normalize = raise "normalization failed"
    end

    feed.stub(:normalizer_class, broken_normalizer) do
      assert_enqueued_with(job: PostPublishJob, args: [feed.id]) do
        error = assert_raises(RuntimeError) { FeedRefreshWorkflow.new(feed).execute }
        assert_equal "normalization failed", error.message
      end
    end

    assert post.reload.enqueued?
    assert_equal "failed", feed.events.where(type: "feed_refresh").sole.metadata["status"]
  end

  test "#execute should not enqueue publication when only another feed has pending posts" do
    entry = create(:feed_entry, feed: feed, status: :processed)
    create(:post, :published, feed: feed, feed_entry: entry)
    create(:post, :enqueued)
    stub_empty_feed

    assert_no_enqueued_jobs(only: PostPublishJob) { FeedRefreshWorkflow.new(feed).execute }
  end
end
