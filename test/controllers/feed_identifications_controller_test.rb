require "test_helper"

class FeedIdentificationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
  end

  def user
    @user ||= create(:user)
  end

  test "#create should require authentication" do
    post feed_identifications_path, params: { input: "http://example.com/feed.xml" }
    assert_redirected_to new_session_path
  end

  test "#create should create feed detail record and enqueue job for valid URL" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    assert_enqueued_with(job: FeedIdentificationJob, args: [user.id, url]) do
      post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    feed_identification = FeedIdentification.find_by(user: user, input: url)
    assert_not_nil feed_identification
    assert_equal "processing", feed_identification.status
    assert_equal url, feed_identification.input
    assert_not_nil feed_identification.started_at
    assert_kind_of ActiveSupport::TimeWithZone, feed_identification.started_at

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
  end

  test "#create should not enqueue job when already processing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success

    assert_no_enqueued_jobs do
      post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
    end
  end

  test "#create should isolate feed detail by user" do
    user2 = create(:user)
    url = "http://example.com/feed.xml"

    sign_in_as(user)
    post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    sign_in_as(user2)
    post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # Both users should have separate feed detail records
    user1_feed_identification = FeedIdentification.find_by(user: user, input: url)
    user2_feed_identification = FeedIdentification.find_by(user: user2, input: url)

    assert_not_nil user1_feed_identification
    assert_not_nil user2_feed_identification
    assert_equal "processing", user1_feed_identification.status
    assert_equal "processing", user2_feed_identification.status
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

    post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    assert_no_enqueued_jobs do
      post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
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
    post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    # Second attempt - should restart identification
    assert_enqueued_with(job: FeedIdentificationJob, args: [user.id, url]) do
      post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, "Checking this feed"
  end

  test "#create should reject empty or malformed input" do
    sign_in_as(user)

    post feed_identifications_path, params: { input: "" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Please enter a link, handle, or a few words"
  end

  test "#create should accept a free-text query as input" do
    sign_in_as(user)

    assert_enqueued_with(job: FeedIdentificationJob) do
      post feed_identifications_path, params: { input: "ai safety news" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
  end

  test "#create should accept a handle as input" do
    sign_in_as(user)

    assert_enqueued_with(job: FeedIdentificationJob) do
      post feed_identifications_path, params: { input: "@alice" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
  end

  test "#show should require authentication" do
    get feed_identifications_path, params: { input: "http://example.com/feed.xml" }
    assert_redirected_to new_session_path
  end

  test "#show should return processing state when status is processing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    # Create processing feed detail via controller
    post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # Check status while still processing (don't perform jobs)
    get feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Checking this feed"
  end

  test "#show should return invalid session error when started_at is missing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    # Create processing feed detail via controller
    post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # Manipulate record to remove started_at (invalid state)
    feed_identification = FeedIdentification.find_by(user: user, input: url)
    feed_identification.update_column(:started_at, nil)

    get feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Identification session is invalid"
    assert_nil FeedIdentification.find_by(user: user, input: url), "Feed identification should be deleted when invalid"
  end

  test "#show should return timeout error when processing exceeds threshold" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    # Create processing feed detail via controller
    post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # Manipulate record to simulate long-running job
    feed_identification = FeedIdentification.find_by(user: user, input: url)
    feed_identification.update_column(:started_at, 31.seconds.ago)

    get feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "taking longer than expected"
    assert_nil FeedIdentification.find_by(user: user, input: url), "Feed identification should be deleted on timeout"
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
    post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

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
    post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    # When no structured profile matches, the AI fallback now fires and the
    # form lands in the complete state instead of the error state.
    assert_includes response.body, 'data-identification-state="complete"'
    assert_includes response.body, "llm_website_extractor"
  end

  test "#show should return error when feed detail is missing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    get feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Identification session expired"
  end

  test "#show should surface a single-candidate payload in the form data-candidates attribute" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    rss_body = "<?xml version=\"1.0\"?><rss><channel><title>Example</title></channel></rss>"
    stub_request(:get, url).to_return(status: 200, body: rss_body)

    post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    payload = extract_candidates_payload(response.body)
    # RSS plus the AI fallback. RSS ranks first.
    assert_equal %w[rss llm_website_extractor], payload.map { |c| c["profile_key"] }
    assert_equal "specific_match", payload.first["rank_reason"]
    assert_equal "ai_fallback", payload.last["rank_reason"]
  end

  test "#show should surface a multi-candidate payload ranked recommended first" do
    sign_in_as(user)
    url = "https://xkcd.com/rss.xml"
    rss_body = "<?xml version=\"1.0\"?><rss><channel><title>xkcd.com</title></channel></rss>"
    stub_request(:get, url).to_return(status: 200, body: rss_body)

    post feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    payload = extract_candidates_payload(response.body)
    assert_equal %w[xkcd rss llm_website_extractor], payload.map { |c| c["profile_key"] }
    assert_equal 0, payload.first["rank"]
    assert_equal "specific_match", payload.first["rank_reason"]
    assert_equal "ai_fallback", payload.last["rank_reason"]
  end

  test "#show should surface an AI-only fallback payload when only an AI matcher fires" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    # Stub the feed_identification directly with an AI-only candidate list — simulates
    # what the fetcher will write when only the llm_website_extractor matches
    # (the AI matcher itself ships in a later PR, so we construct the payload
    # here as a stand-in to exercise the controller payload contract today).
    feed_identification = FeedIdentification.create!(
      user: user,
      input: url,
      status: :success,
      candidates: [
        { "profile_key" => "llm_website_extractor", "title" => "Example", "depends_on_ai" => true, "rank" => 0, "rank_reason" => "ai_fallback" }
      ]
    )

    get feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    payload = extract_candidates_payload(response.body)
    assert_equal 1, payload.size
    assert_equal "llm_website_extractor", payload.first["profile_key"]
    assert_equal true, payload.first["depends_on_ai"]
    assert_equal "ai_fallback", payload.first["rank_reason"]
  ensure
    feed_identification&.destroy
  end

  test "#show should show the AI cost notice when a non-recommended candidate is AI" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    feed_identification = FeedIdentification.create!(
      user: user,
      input: url,
      status: :success,
      candidates: [
        { "profile_key" => "rss", "title" => "Example", "depends_on_ai" => false, "rank" => 0, "rank_reason" => "" },
        { "profile_key" => "llm_website_extractor", "title" => "Example", "depends_on_ai" => true, "rank" => 1, "rank_reason" => "ai_fallback" }
      ]
    )

    get feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "[data-key='ai-cost.notice']", count: 1
  ensure
    feed_identification&.destroy
  end

  test "#show should preselect the default schedule interval with no blank option" do
    sign_in_as(user)
    create(:access_token, :active, user: user)
    url = "http://example.com/feed.xml"
    feed_identification = FeedIdentification.create!(
      user: user,
      input: url,
      status: :success,
      candidates: [
        { "profile_key" => "rss", "title" => "Example", "depends_on_ai" => false, "rank" => 0, "rank_reason" => "" }
      ]
    )

    get feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "select[name='feed[schedule_interval]'] option[value='']", count: 0
    assert_select "select[name='feed[schedule_interval]'] option[selected='selected']" do |options|
      assert_equal Feed::DEFAULT_SCHEDULE_INTERVAL, options.first["value"]
    end
  ensure
    feed_identification&.destroy
  end

  test "#show should preselect the first active access token with no blank option" do
    sign_in_as(user)
    first_token = create(:access_token, :active, user: user, host: "https://aaa.freefeed.net")
    create(:access_token, :active, user: user, host: "https://zzz.freefeed.net")
    url = "http://example.com/feed.xml"
    feed_identification = FeedIdentification.create!(
      user: user,
      input: url,
      status: :success,
      candidates: [
        { "profile_key" => "rss", "title" => "Example", "depends_on_ai" => false, "rank" => 0, "rank_reason" => "" }
      ]
    )

    get feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "select[name='feed[access_token_id]'] option[value='']", count: 0
    assert_select "select[name='feed[access_token_id]'] option[selected='selected']" do |options|
      assert_equal first_token.id.to_s, options.first["value"]
    end
  ensure
    feed_identification&.destroy
  end

  test "#show should write the user's input under params[query] for handle inputs" do
    sign_in_as(user)
    handle = "@alice"
    create(
      :feed_identification,
      user: user,
      input: handle,
      started_at: Time.current,
      status: :success,
      candidates: [
        { "profile_key" => "llm_web_search", "title" => nil, "depends_on_ai" => true, "rank" => 0, "rank_reason" => "ai_fallback" }
      ]
    )

    get feed_identifications_path, params: { input: handle }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, 'name="feed[params][query]"'
    assert_includes response.body, "value=\"#{handle}\""
    refute_includes response.body, 'name="feed[params][url]"'
  end

  test "#show should write the user's input under params[query] for query profiles" do
    sign_in_as(user)
    query = "climate change"
    create(
      :feed_identification,
      user: user,
      input: query,
      started_at: Time.current,
      status: :success,
      candidates: [
        { "profile_key" => "llm_web_search", "title" => nil, "depends_on_ai" => true, "rank" => 0, "rank_reason" => "ai_fallback" }
      ]
    )

    get feed_identifications_path, params: { input: query }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, 'name="feed[params][query]"'
    refute_includes response.body, 'name="feed[params][url]"'
  end

  test "#destroy should require authentication" do
    delete feed_identifications_path
    assert_redirected_to new_session_path
  end

  test "#destroy should remove the user's in-progress feed_identification and re-render collapsed form" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    create(:feed_identification, user: user, input: url, status: :processing, started_at: Time.current)

    assert_difference("FeedIdentification.count", -1) do
      delete feed_identifications_path,
             params: { input: url },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
    assert_includes response.body, 'id="feed-form"'
    assert_includes response.body, url
  end

  test "#destroy should be idempotent and echo the typed URL when no feed_identification exists" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    assert_no_difference("FeedIdentification.count") do
      delete feed_identifications_path,
             params: { input: url },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, url
  end

  test "#show should render the candidate chooser when multiple candidates exist" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    create(
      :feed_identification,
      user: user,
      input: url,
      started_at: Time.current,
      status: :success,
      candidates: [
        { "profile_key" => "rss", "title" => "Example", "depends_on_ai" => false, "rank" => 0, "rank_reason" => "specific_match" },
        { "profile_key" => "llm_website_extractor", "title" => "Example", "depends_on_ai" => true, "rank" => 1, "rank_reason" => "ai_fallback" }
      ]
    )

    get feed_identifications_path, params: { input: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

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
