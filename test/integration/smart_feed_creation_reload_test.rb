require "test_helper"

# FR-018 + FR-019 reload semantics: reloading an in-progress confirmation
# does not re-run detection or the preview. An explicit Refresh control
# re-runs the preview on demand.
class SmartFeedCreationReloadTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  def feed_url
    "http://example.com/feed.xml"
  end

  def rss_body
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Example Feed</title>
          <link>http://example.com</link>
          <item>
            <title>Post</title>
            <link>http://example.com/post</link>
            <guid>http://example.com/post</guid>
            <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
          </item>
        </channel>
      </rss>
    XML
  end

  def with_memory_cache
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = previous
  end

  test "#get should not re-enqueue detection when the feed_detail is already success" do
    sign_in_as(user)
    stub_request(:get, feed_url).to_return(status: 200, body: rss_body)

    post feed_details_path, params: { url: feed_url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    assert_no_enqueued_jobs do
      get feed_details_path, params: { url: feed_url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "#get on the live preview should not re-enqueue the preview job on a cache hit" do
    sign_in_as(user)

    with_memory_cache do
      stub_request(:get, feed_url).to_return(status: 200, body: rss_body)
      # First fetch warms the cache via the preview service.
      FeedPreviewService.call(
        user: user,
        profile_key: "rss",
        params: { "url" => feed_url },
        cache_key: cache_key
      )

      assert_no_enqueued_jobs do
        get feed_live_preview_path("draft"),
            params: { profile_key: "rss", params: { url: feed_url } }
      end
    end
  end

  test "#post on the live preview should re-enqueue the job with refresh" do
    sign_in_as(user)

    with_memory_cache do
      stub_request(:get, feed_url).to_return(status: 200, body: rss_body)
      FeedPreviewService.call(
        user: user,
        profile_key: "rss",
        params: { "url" => feed_url },
        cache_key: cache_key
      )

      assert_enqueued_with(job: FeedPreviewJob) do
        post feed_live_preview_path("draft"),
             params: { profile_key: "rss", params: { url: feed_url } }
      end
    end
  end

  private

  def cache_key
    canonical = { "url" => feed_url }.deep_stringify_keys.sort.to_h.to_json
    "preview:draft:#{user.id}:rss:#{Digest::SHA256.hexdigest(canonical)}"
  end
end
