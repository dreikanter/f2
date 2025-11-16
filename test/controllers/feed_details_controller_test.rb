require "test_helper"

class FeedDetailsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
  end

  def user
    @user ||= create(:user)
  end

  def cache_key(url)
    FeedIdentificationCache.key_for(user.id, url)
  end

  test "#create should require authentication" do
    post feed_details_path, params: { url: "http://example.com/feed.xml" }
    assert_redirected_to new_session_path
  end

  test "#create should create cache entry and enqueue job for valid URL" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    with_caching do
      assert_enqueued_with(job: FeedDetailsJob, args: [user.id, url]) do
        post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
  end

  test "#create should reuse existing cache entry if present" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    with_caching do
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success

      assert_no_enqueued_jobs do
        post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
        assert_response :success
      end
    end
  end

  test "#create should reuse successful identification from cache" do
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

    with_caching do
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      perform_enqueued_jobs

      assert_no_enqueued_jobs do
        post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
    assert_includes response.body, "Feed identified: rss"
    assert_includes response.body, 'data-identification-state="complete"'
  end

  test "#create should restart identification for failed cache entry" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    stub_request(:get, url)
      .to_return(status: 404, body: "Not Found")

    with_caching do
      # First attempt - creates failed cache entry
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      perform_enqueued_jobs

      # Second attempt - should restart identification
      assert_enqueued_with(job: FeedDetailsJob, args: [user.id, url]) do
        post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end

      assert_response :success
      assert_includes response.body, "Checking this feed"
    end
  end

  test "#create should return error for invalid URL" do
    sign_in_as(user)

    post feed_details_path, params: { url: "not-a-url" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Please enter a valid URL"
    assert_includes response.body, 'target="feed-form"'
  end

  test "#create should return error for empty URL" do
    sign_in_as(user)

    post feed_details_path, params: { url: "" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Please enter a valid URL"
  end

  test "#create should return loading state turbo stream" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "turbo-stream"
    assert_includes response.body, 'action="replace"'
    assert_includes response.body, 'target="feed-form"'
    assert_includes response.body, "Checking this feed"
  end

  test "#show should require authentication" do
    get feed_details_path, params: { url: "http://example.com/feed.xml" }
    assert_redirected_to new_session_path
  end

  test "#show should return processing state when status is processing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    with_caching do
      # Create processing cache entry via controller
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      # Check status while still processing (don't perform jobs)
      get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_includes response.body, "Checking this feed"
    end
  end

  test "#show should return invalid session error when started_at is missing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    with_caching do
      # Create processing cache entry via controller
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      # Manipulate cache to remove started_at (invalid state)
      cached_data = Rails.cache.read(cache_key(url))
      Rails.cache.write(
        cache_key(url),
        cached_data.except(:started_at),
        expires_in: 10.minutes
      )

      get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_includes response.body, "Identification session is invalid"
      assert_nil Rails.cache.read(cache_key(url)), "Cache entry should be deleted when invalid"
    end
  end

  test "#show should return timeout error when processing exceeds threshold" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    with_caching do
      # Create processing cache entry via controller
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      # Manipulate cache to simulate long-running job
      cached_data = Rails.cache.read(cache_key(url))
      Rails.cache.write(
        cache_key(url),
        cached_data.merge(started_at: 31.seconds.ago),
        expires_in: 10.minutes
      )

      get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_includes response.body, "taking longer than expected"
      assert_nil Rails.cache.read(cache_key(url)), "Cache entry should be deleted on timeout"
    end
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

    with_caching do
      # Create successful cache entry via controller and job
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      perform_enqueued_jobs

      get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_includes response.body, 'action="replace"'
      assert_includes response.body, 'target="feed-form"'
    end
  end

  test "#show should return error when status is failed" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    stub_request(:get, url)
      .to_return(status: 200, body: "Not a valid feed", headers: { "Content-Type" => "text/plain" })

    with_caching do
      # Create failed cache entry via controller and job
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      perform_enqueued_jobs

      get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_includes response.body, "Could not identify feed profile"
      assert_includes response.body, 'data-identification-state="error"'
    end
  end

  test "#show should return error when cache entry is missing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Identification session expired"
  end

  test "#show should use default error message when failed status has no error" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    stub_request(:get, url)
      .to_return(status: 200, body: "Not a valid feed", headers: { "Content-Type" => "text/plain" })

    with_caching do
      # Create failed cache entry via controller and job
      post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      perform_enqueued_jobs

      # Manipulate cache to remove error field (edge case)
      cached_data = Rails.cache.read(cache_key(url))
      Rails.cache.write(
        cache_key(url),
        cached_data.except(:error),
        expires_in: 10.minutes
      )

      get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_includes response.body, "We couldn&#39;t identify a feed profile for this URL"
    end
  end
end
