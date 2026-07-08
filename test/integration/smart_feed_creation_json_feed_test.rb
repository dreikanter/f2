require "test_helper"

# Integration test for the JSON Feed happy path.
# Walks paste → detection → preview cache → save → enabled feed.
class SmartFeedCreationJsonFeedTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def feed_url
    "http://example.com/feed.json"
  end

  def json_body
    @json_body ||= <<~JSON
      {
        "version": "https://jsonfeed.org/version/1.1",
        "title": "Example JSON Feed",
        "home_page_url": "http://example.com/",
        "feed_url": "http://example.com/feed.json",
        "items": [
          {
            "id": "http://example.com/post1",
            "url": "http://example.com/post1",
            "title": "First post",
            "content_html": "<p>Hello world</p>",
            "date_published": "2024-01-01T00:00:00Z"
          }
        ]
      }
    JSON
  end

  def with_memory_cache
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = previous
  end

  test "#post should drive JSON Feed happy path: paste, detect, preview, save enabled" do
    sign_in_as(user)
    access_token
    stub_request(:get, feed_url)
      .to_return(status: 200, body: json_body, headers: { "Content-Type" => "application/feed+json" })

    with_memory_cache do
      post feed_identifications_path, params: { url: feed_url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success

      perform_enqueued_jobs

      get feed_identifications_path, params: { url: feed_url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_includes response.body, 'data-identification-state="complete"'
      assert_includes response.body, "JSON Feed"

      post feed_preview_path(profile_key: "json_feed", "params" => { "url" => feed_url })
      assert_response :success

      perform_enqueued_jobs

      preview = FeedPreview.last
      assert_predicate preview, :ready?, "preview should be ready after the job runs"

      assert_difference("Feed.count", 1) do
        post feeds_path, params: {
          feed: {
            url: feed_url,
            name: "Example JSON Feed",
            feed_profile_key: "json_feed",
            access_token_id: access_token.id,
            target_group: "testgroup",
            schedule_interval: "1h"
          },
          enable_feed: "1"
        }
      end

      feed = Feed.last
      assert_equal "enabled", feed.state
      assert_equal "json_feed", feed.feed_profile_key
      assert_equal feed_url, feed.url
    end
  end
end
