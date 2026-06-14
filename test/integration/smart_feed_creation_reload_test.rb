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

  test "#create should not re-enqueue detection when the feed_identification is already success" do
    sign_in_as(user)
    stub_request(:get, feed_url).to_return(status: 200, body: rss_body)

    post feed_identifications_path, params: { input: feed_url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    assert_no_enqueued_jobs do
      post feed_identifications_path, params: { input: feed_url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "#show on an existing ready preview should not re-enqueue the preview job" do
    sign_in_as(user)
    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
           params: { "url" => feed_url }, ready_at: Time.current)

    assert_no_enqueued_jobs do
      get feed_preview_path(profile_key: "rss", "params" => { "url" => feed_url })
    end
  end

  test "#create should re-enqueue the preview job to refresh" do
    sign_in_as(user)
    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
           params: { "url" => feed_url }, ready_at: Time.current)

    assert_enqueued_with(job: FeedPreviewJob) do
      post feed_preview_path(profile_key: "rss", "params" => { "url" => feed_url })
    end
  end
end
