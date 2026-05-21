require "test_helper"

# Integration test for User Story 1 (RSS happy path).
# Walks paste → detection → preview cache → save → enabled feed.
class SmartFeedCreationRssTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def feed_url
    "http://example.com/feed.xml"
  end

  def rss_body
    @rss_body ||= <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Example Feed</title>
          <description>A sample feed</description>
          <item>
            <title>First post</title>
            <link>http://example.com/post1</link>
            <description>Hello world</description>
            <guid>http://example.com/post1</guid>
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

  test "#post should drive RSS happy path: paste, detect, preview, save enabled" do
    sign_in_as(user)
    access_token
    stub_request(:get, feed_url)
      .to_return(status: 200, body: rss_body, headers: { "Content-Type" => "application/xml" })

    with_memory_cache do
      post feed_identifications_path, params: { url: feed_url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success

      perform_enqueued_jobs

      get feed_identifications_path, params: { url: feed_url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_includes response.body, 'data-identification-state="complete"'
      assert_includes response.body, "RSS Feed"

      get feed_live_preview_path("draft"),
          params: { profile_key: "rss", params: { url: feed_url } }
      assert_response :success

      perform_enqueued_jobs

      preview = FeedPreviewService.call(
        user: user,
        profile_key: "rss",
        params: { "url" => feed_url }
      )
      assert preview.preview_token.present?, "preview should issue a token"

      assert_difference("Feed.count", 1) do
        post feeds_path, params: {
          feed: {
            url: feed_url,
            name: "Example Feed",
            feed_profile_key: "rss",
            access_token_id: access_token.id,
            target_group: "testgroup",
            schedule_interval: "1h"
          },
          enable_feed: "1",
          preview_token: preview.preview_token
        }
      end

      feed = Feed.last
      assert_equal "enabled", feed.state
      assert_equal "Example Feed", feed.name
      assert_equal feed_url, feed.url
      assert_nil FeedIdentification.find_by(user: user, url: feed_url), "FeedIdentification should be cleaned up after save"
    end
  end

  test "#post should rank XKCD profile above generic RSS for an xkcd.com URL" do
    sign_in_as(user)
    xkcd_url = "https://xkcd.com/"
    stub_request(:get, xkcd_url)
      .to_return(status: 200, body: rss_body, headers: { "Content-Type" => "application/xml" })

    with_memory_cache do
      post feed_identifications_path, params: { url: xkcd_url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      perform_enqueued_jobs

      get feed_identifications_path, params: { url: xkcd_url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_includes response.body, "XKCD"
    end
  end

  test "#delete should return user to collapsed form with their input preserved" do
    sign_in_as(user)
    create(:feed_identification, user: user, url: feed_url, status: :processing, started_at: Time.current)

    assert_difference("FeedIdentification.count", -1) do
      delete feed_identifications_path,
             params: { url: feed_url },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, 'id="feed-form"'
    assert_includes response.body, feed_url
    assert_includes response.body, "What do you want to follow?"
  end
end
