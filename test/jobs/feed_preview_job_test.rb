require "test_helper"

class FeedPreviewJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  def feed_url
    "https://example.com/feed.xml"
  end

  def rss_body
    @rss_body ||= file_fixture("feeds/rss/feed.xml").read
  end

  def with_memory_cache
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = previous
  end

  def perform_args(overrides = {})
    {
      "user_id" => user.id,
      "profile_key" => "rss",
      "params" => { "url" => feed_url },
      "cache_key" => "preview:abc"
    }.merge(overrides.transform_keys(&:to_s))
  end

  test "should be queued on default queue" do
    assert_equal "default", FeedPreviewJob.queue_name
  end

  test "should inherit from ApplicationJob" do
    assert_equal ApplicationJob, FeedPreviewJob.superclass
  end

  test "#perform should write a successful preview into the cache" do
    with_memory_cache do
      stub_request(:get, feed_url)
        .to_return(status: 200, body: rss_body, headers: { "Content-Type" => "application/xml" })

      FeedPreviewJob.perform_now(perform_args)

      cached = Rails.cache.read("preview:abc")
      assert_kind_of FeedPreviewService::Preview, cached
      assert_predicate cached.posts, :any?
    end
  end

  test "#perform should write a failure marker when the source is unreachable" do
    with_memory_cache do
      stub_request(:get, feed_url).to_return(status: 500, body: "boom")

      FeedPreviewJob.perform_now(perform_args)

      cached = Rails.cache.read("preview:abc")
      assert cached.is_a?(Hash)
      assert_equal "SourceUnreachable", cached[:error]
    end
  end

  test "#perform should write a failure marker when the feed has no entries" do
    empty_rss = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Empty</title>
          <description>Empty feed</description>
          <link>https://example.com</link>
        </channel>
      </rss>
    XML
    with_memory_cache do
      stub_request(:get, feed_url)
        .to_return(status: 200, body: empty_rss, headers: { "Content-Type" => "application/xml" })

      FeedPreviewJob.perform_now(perform_args)

      cached = Rails.cache.read("preview:abc")
      assert cached.is_a?(Hash)
      assert_equal "Empty", cached[:error]
    end
  end

  test "#perform should accept a limit override and pass it to the service" do
    with_memory_cache do
      stub_request(:get, feed_url)
        .to_return(status: 200, body: rss_body, headers: { "Content-Type" => "application/xml" })

      FeedPreviewJob.perform_now(perform_args("limit" => 2))

      cached = Rails.cache.read("preview:abc")
      assert_operator cached.posts.size, :<=, 2
    end
  end

  test "#perform should enqueue with the canonical args via perform_later" do
    assert_enqueued_with(job: FeedPreviewJob) do
      FeedPreviewJob.perform_later(perform_args)
    end
  end
end
