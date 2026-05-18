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
    assert_includes response.body, 'action="replace"'
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

  test "#show should surface a single-candidate payload in the form data-candidates attribute" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    rss_body = "<?xml version=\"1.0\"?><rss><channel><title>Example</title></channel></rss>"
    stub_request(:get, url).to_return(status: 200, body: rss_body)

    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    payload = extract_candidates_payload(response.body)
    assert_equal 1, payload.size
    assert_equal "rss", payload.first["profile_key"]
    assert_equal "specific_match", payload.first["rank_reason"]
  end

  test "#show should surface a multi-candidate payload ranked recommended first" do
    sign_in_as(user)
    url = "https://xkcd.com/rss.xml"
    rss_body = "<?xml version=\"1.0\"?><rss><channel><title>xkcd.com</title></channel></rss>"
    stub_request(:get, url).to_return(status: 200, body: rss_body)

    post feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    payload = extract_candidates_payload(response.body)
    assert_equal %w[xkcd rss], payload.map { |c| c["profile_key"] }
    assert_equal 0, payload.first["rank"]
    assert_equal "specific_match", payload.first["rank_reason"]
    assert_equal "generic_match", payload.last["rank_reason"]
  end

  test "#show should surface an AI-only fallback payload when only an AI matcher fires" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    # Stub the feed_detail directly with an AI-only candidate list — simulates
    # what the fetcher will write when only the llm_website_extractor matches
    # (the AI matcher itself ships in a later PR, so we construct the payload
    # here as a stand-in to exercise the controller payload contract today).
    feed_detail = FeedDetail.create!(
      user: user,
      url: url,
      status: :success,
      candidates: [
        { "profile_key" => "llm_website_extractor", "title" => "Example", "depends_on_ai" => true, "rank" => 0, "rank_reason" => "ai_fallback" }
      ]
    )

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    payload = extract_candidates_payload(response.body)
    assert_equal 1, payload.size
    assert_equal "llm_website_extractor", payload.first["profile_key"]
    assert_equal true, payload.first["depends_on_ai"]
    assert_equal "ai_fallback", payload.first["rank_reason"]
  ensure
    feed_detail&.destroy
  end

  test "#destroy should require authentication" do
    delete feed_details_path
    assert_redirected_to new_session_path
  end

  test "#destroy should remove the user's in-progress feed_detail and re-render collapsed form" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    create(:feed_detail, user: user, url: url, status: :processing, started_at: Time.current)

    assert_difference("FeedDetail.count", -1) do
      delete feed_details_path,
             params: { url: url },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
    assert_includes response.body, 'id="feed-form"'
    assert_includes response.body, url
  end

  test "#destroy should be idempotent and echo the typed URL when no feed_detail exists" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    assert_no_difference("FeedDetail.count") do
      delete feed_details_path,
             params: { url: url },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, url
  end

  test "#show should render the candidate chooser when multiple candidates exist" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    create(
      :feed_detail,
      user: user,
      url: url,
      started_at: Time.current,
      status: :success,
      candidates: [
        { "profile_key" => "rss", "title" => "Example", "depends_on_ai" => false, "rank" => 0, "rank_reason" => "specific_match" },
        { "profile_key" => "llm_website_extractor", "title" => "Example", "depends_on_ai" => true, "rank" => 1, "rank_reason" => "ai_fallback" }
      ]
    )

    get feed_details_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "data-key=\"candidates\""
    assert_includes response.body, "data-key=\"candidate.rss\""
    assert_includes response.body, "data-key=\"candidate.llm_website_extractor\""
    assert_includes response.body, "data-key=\"candidate.ai-badge\""
  end

  private

  def extract_candidates_payload(body)
    # The form swap puts data-candidates="<json>" on the wrapper. Capybara/
    # Nokogiri would be overkill; a regex over the escaped JSON works for the
    # contract here. The view always renders this attribute on
    # data-identification-state="complete".
    match = body.match(/data-candidates="(?<json>[^"]*)"/)
    return [] unless match

    JSON.parse(CGI.unescapeHTML(match[:json]))
  end
end
