require "test_helper"

class FeedDetailsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
  end

  def user
    @user ||= create(:user)
  end

  test "#create should require authentication" do
    post feed_details_path, params: { url: "http://example.com/feed.xml" }
    assert_redirected_to new_session_path
  end

  test "#create should create feed detail record and enqueue job for valid URL" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    assert_enqueued_with(job: FeedDetailsJob, args: [user.id, url]) do
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    feed_detail = FeedDetail.find_by(user: user, url: url)
    assert_not_nil feed_detail
    assert_equal "processing", feed_detail.status
    assert_equal url, feed_detail.url
    assert_not_nil feed_detail.started_at
    assert_kind_of ActiveSupport::TimeWithZone, feed_detail.started_at

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
  end

  test "#create should not enqueue job when already processing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success

    assert_no_enqueued_jobs do
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
    end
  end

  test "#create should isolate feed detail by user" do
    user2 = create(:user)
    url = "http://example.com/feed.xml"

    sign_in_as(user)
    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    sign_in_as(user2)
    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # Both users should have separate feed detail records
    user1_feed_detail = FeedDetail.find_by(user: user, url: url)
    user2_feed_detail = FeedDetail.find_by(user: user2, url: url)

    assert_not_nil user1_feed_detail
    assert_not_nil user2_feed_detail
    assert_equal "processing", user1_feed_detail.status
    assert_equal "processing", user2_feed_detail.status
  end

  test "#create should reuse successful feed detail" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Example Feed</title>
          <description>Test Description</description>
          <link>http://example.com</link>
          <item>
            <title>Test Post</title>
            <description>Test content</description>
            <link>http://example.com/post1</link>
          </item>
        </channel>
      </rss>
    XML

    stub_request(:get, url)
      .to_return(status: 200, body: rss_content, headers: { "Content-Type" => "application/xml" })

    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    assert_no_enqueued_jobs do
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, 'data-identification-state="complete"'
    assert_includes response.body, "Feed Type"
    assert_includes response.body, "RSS Feed"
  end

  test "#create should restart identification for failed feed detail" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    stub_request(:get, url)
      .to_return(status: 404, body: "Not Found")

    # First attempt - creates failed feed detail
    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    # Second attempt - should restart identification
    assert_enqueued_with(job: FeedDetailsJob, args: [user.id, url]) do
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, "Checking this feed"
  end

  test "#create should return error for invalid URL" do
    sign_in_as(user)

    post feed_details_path, params: { url: "not-a-url" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Please enter a valid URL"
  end

  test "#show should require authentication" do
    get feed_details_path, params: { url: "http://example.com/feed.xml" }
    assert_redirected_to new_session_path
  end

  test "#show should return processing state when status is processing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    # Create processing feed detail via controller
    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # Check status while still processing (don't perform jobs)
    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Checking this feed"
  end

  test "#show should return invalid session error when started_at is missing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    # Create processing feed detail via controller
    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # Manipulate record to remove started_at (invalid state)
    feed_detail = FeedDetail.find_by(user: user, url: url)
    feed_detail.update_column(:started_at, nil)

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Identification session is invalid"
    assert_nil FeedDetail.find_by(user: user, url: url), "Feed detail should be deleted when invalid"
  end

  test "#show should return timeout error when processing exceeds threshold" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    # Create processing feed detail via controller
    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # Manipulate record to simulate long-running job
    feed_detail = FeedDetail.find_by(user: user, url: url)
    feed_detail.update_column(:started_at, 31.seconds.ago)

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "taking longer than expected"
    assert_nil FeedDetail.find_by(user: user, url: url), "Feed detail should be deleted on timeout"
  end

  test "#show should return expanded form when status is success" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <description>Test Description</description>
          <link>http://example.com</link>
        </channel>
      </rss>
    XML

    stub_request(:get, url)
      .to_return(status: 200, body: rss_content, headers: { "Content-Type" => "application/xml" })

    # Create successful feed detail via controller and job
    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, 'action="update"'
    assert_includes response.body, 'target="feed-form"'
  end

  test "#show should return error when status is failed" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    stub_request(:get, url)
      .to_return(status: 200, body: "Not a valid feed", headers: { "Content-Type" => "text/plain" })

    # Create failed feed detail via controller and job
    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Unsupported feed profile"
    assert_includes response.body, 'data-identification-state="error"'
  end

  test "#show should return error when feed detail is missing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Identification session expired"
  end
end
