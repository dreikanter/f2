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
    post feed_identifications_path, params: { url: "http://example.com/feed.xml" }
    assert_redirected_to new_session_path
  end

  test "#create should create feed detail record and enqueue job for valid URL" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    assert_enqueued_with(job: FeedIdentificationJob, args: [user.id, url]) do
      post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
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

    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success

    assert_no_enqueued_jobs do
      post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
    end
  end

  test "#create should isolate feed detail by user" do
    user2 = create(:user)
    url = "http://example.com/feed.xml"

    sign_in_as(user)
    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    sign_in_as(user2)
    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

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
            <guid>http://example.com/post1</guid>
            <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
          </item>
        </channel>
      </rss>
    XML

    stub_request(:get, url)
      .to_return(status: 200, body: rss_content, headers: { "Content-Type" => "application/xml" })

    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    assert_no_enqueued_jobs do
      post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
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
    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    # Second attempt - should restart identification
    assert_enqueued_with(job: FeedIdentificationJob, args: [user.id, url]) do
      post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, "Checking this feed"
  end

  test "#create should not enqueue a duplicate detection when losing the restart race" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    winner = create(:feed_identification, user: user, input: url, started_at: Time.current).reload
    # The loser's stale lookup result: it missed the winner's row, so its
    # insert inside restart_detection! collides with the user+input unique index.
    loser = FeedIdentification.new(user: user, input: url)

    FeedIdentification.stub(:find_or_initialize_by, loser) do
      assert_no_enqueued_jobs(only: FeedIdentificationJob) do
        post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
    assert_includes response.body, 'data-identification-state="checking"'
    assert_equal winner.started_at, winner.reload.started_at, "the winner's detection should not be restarted"
  end

  test "#create should freeze the entry form while detection runs" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, 'data-identification-state="checking"'
    assert_select "input#entry-link-input[disabled][value=?]", url
    assert_select "input[type=submit][value='Checking…'][disabled]"
    assert_select "[data-key='entry.mode-ai'] input[type=radio][disabled]"
    # Cancel stays live as the escape hatch: it aborts the check and re-renders
    # the form with the URL kept.
    assert_select "a[data-key='entry.cancel-check'][data-turbo-method='delete']"
  end

  test "#create should ask for input when it is blank" do
    sign_in_as(user)

    post feed_identifications_path, params: { url: "" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Enter a link"
  end

  test "#create should bridge the webhook mode straight to a draft webhook feed" do
    sign_in_as(user)

    assert_no_enqueued_jobs(only: FeedIdentificationJob) do
      post feed_identifications_path, params: { webhook: "1" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, 'data-identification-state="complete"'
    assert_select "input[type=hidden][name='feed[feed_profile_key]'][value='webhook']", count: 1
    assert_select "input[type=text][name='feed[params][url]']", count: 0
    assert_select "textarea[name='feed[params][prompt]']", count: 0
    # No source, no preview, no schedule — the webhook note takes their place.
    assert_select "[data-key='form.webhook-note']", count: 1
    assert_select "[data-key='preview.open']", count: 0
    assert_select "select[name='feed[schedule_interval]']", count: 0
  end

  test "#create should bridge a Mode B prompt straight to a draft AI feed" do
    sign_in_as(user)

    assert_no_enqueued_jobs(only: FeedIdentificationJob) do
      post feed_identifications_path, params: { prompt: "ai safety news" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, 'data-identification-state="complete"'
    assert_includes response.body, "ai safety news"
  end

  test "#create should hint at the AI mode and carry the text over when a Mode A input isn't a link" do
    sign_in_as(user)

    assert_no_enqueued_jobs(only: FeedIdentificationJob) do
      post feed_identifications_path, params: { url: "@alice" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, 'data-identification-state="error"'
    assert_includes response.body, "look like a link"
    # The user stays in the mode they chose (spec §1); the AI panel carries the
    # text so switching the radio is the bridge.
    assert_select "[data-key='entry.mode-link'] input[type=radio][checked]"
    assert_select "[data-key='entry.error']", text: /look like a link/
    assert_select "textarea#entry-ai-input", text: "@alice"
  end

  test "#create should not persist an identification record on the AI bridge" do
    sign_in_as(user)

    assert_no_difference("FeedIdentification.count") do
      post feed_identifications_path, params: { prompt: "climate change" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "#create should treat whitespace-only input as blank" do
    sign_in_as(user)

    post feed_identifications_path, params: { url: "   " }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Enter a link"
  end

  test "#create should build a draft AI feed for an explicit AI-bridge request" do
    sign_in_as(user)

    assert_no_enqueued_jobs(only: FeedIdentificationJob) do
      post feed_identifications_path, params: { prompt: "https://example.com/page" },
                                      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, 'data-identification-state="complete"'
    assert_includes response.body, "https://example.com/page"
  end

  test "#create should give a bridged AI feed an editable prompt" do
    sign_in_as(user)

    post feed_identifications_path, params: { prompt: "follow the A24 blog" },
                                    headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    # The prompt is the source, so it stays editable while creating (spec §1);
    # exactly one prompt field, and the profile key still submits.
    assert_select "textarea[name='feed[params][prompt]']", { count: 1, text: "follow the A24 blog" }
    assert_select "input[type=text][name='feed[params][url]']", count: 0
    assert_select "input[type=hidden][name='feed[feed_profile_key]'][value='llm']", count: 1
  end

  test "#create should default a bridged AI feed to a daily schedule" do
    sign_in_as(user)

    post feed_identifications_path, params: { prompt: "follow the A24 blog" },
                                    headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "select[name='feed[schedule_interval]'] option[value='1d'][selected='selected']"
  end

  test "#show should require authentication" do
    get feed_identifications_path, params: { url: "http://example.com/feed.xml" }
    assert_redirected_to new_session_path
  end

  test "#show should return no content while still processing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    # Create processing feed detail via controller
    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # Check status while still processing (don't perform jobs)
    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :no_content
    assert_empty response.body
  end

  test "#show should return error when started_at is missing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    # Create processing feed detail via controller
    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # Manipulate record to remove started_at (invalid state)
    feed_identification = FeedIdentification.find_by(user: user, input: url)
    feed_identification.update_column(:started_at, nil)

    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "Error identifying feed"
    assert_nil FeedIdentification.find_by(user: user, input: url), "Feed identification should be deleted when invalid"
  end

  test "#show should return timeout error when processing exceeds threshold" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    # Create processing feed detail via controller
    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # Manipulate record to simulate a job stuck well past the timeout
    feed_identification = FeedIdentification.find_by(user: user, input: url)
    feed_identification.update_column(:started_at, 10.minutes.ago)

    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

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
    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, 'data-identification-state="complete"'
  end

  test "#show should return error when status is failed" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    stub_request(:get, url)
      .to_return(status: 200, body: "Not a valid feed", headers: { "Content-Type" => "text/plain" })

    # Create failed feed detail via controller and job
    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    # No structured profile matches and detection can't select AI (spec §7), so
    # the form re-renders with the no-feed hint pointing at the AI mode.
    assert_includes response.body, 'data-identification-state="error"'
    assert_select "[data-key='entry.error']", text: /pull any posts/
  end

  test "#show should show the transient retry hint when the source can't be reached" do
    sign_in_as(user)
    url = "http://example.com/down.xml"

    stub_request(:get, url).to_timeout

    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs
    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, 'data-identification-state="error"'
    # Resubmitting the preserved URL is the retry; the AI panel stays as the
    # secondary escape with the text carried over.
    assert_select "[data-key='entry.error']", text: /couldn't reach that link/i
    assert_select "input#entry-link-input[value=?]", url
    assert_select "textarea#entry-ai-input", text: url
  end

  test "#create should re-run detection when retrying a couldn't-reach success" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    # A success whose only candidate was unreachable: Retry must re-detect rather
    # than re-render the same couldn't-reach state.
    create(:feed_identification, user: user, input: url, started_at: Time.current, status: :success,
                                 candidates: [{ "profile_key" => "youtube", "test_status" => "unreachable" }])

    assert_enqueued_with(job: FeedIdentificationJob) do
      post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_select "[data-controller*='polling']"
    assert_includes response.body, 'data-identification-state="checking"'
  end

  test "#show should show the terminal no-feed error when a reachable link has no working feed" do
    sign_in_as(user)
    url = "http://example.com/page.html"
    create(:feed_identification, user: user, input: url, started_at: Time.current, status: :success,
                                 candidates: [{ "profile_key" => "rss", "test_status" => "failed" }])

    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, 'data-identification-state="error"'
    assert_includes response.body, "pull any posts"
    assert_select "textarea#entry-ai-input", text: url
  end

  test "#show should return error when feed detail is missing" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"

    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "That check expired"
  end

  test "#show should render a single working candidate as a fixed feed type" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    rss_body = "<?xml version=\"1.0\"?><rss><channel><title>Example</title></channel></rss>"
    stub_request(:get, url).to_return(status: 200, body: rss_body)

    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "input[type=hidden][name='feed[feed_profile_key]'][value=?]", "rss"
    assert_select "input[data-key='form.feed-type-display'][value=?]", "RSS Feed"
    assert_select "[data-key='candidates']", count: 0
  end

  test "#show should render the chooser with the suggested candidate first" do
    sign_in_as(user)
    url = "https://xkcd.com/rss.xml"
    rss_body = "<?xml version=\"1.0\"?><rss><channel><title>xkcd.com</title></channel></rss>"
    stub_request(:get, url).to_return(status: 200, body: rss_body)

    post feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    perform_enqueued_jobs

    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal ["candidate.xkcd", "candidate.rss"],
                 css_select("label[data-key^='candidate.']").map { |node| node["data-key"] }
    assert_select "label[data-key='candidate.xkcd'] input[type=radio][value=?][checked=checked]", "xkcd"
    assert_select "label[data-key='candidate.xkcd'] [data-key='candidate.suggested-badge']"
  end

  test "#show should preselect the default schedule interval with no blank option" do
    sign_in_as(user)
    create(:access_token, :active, user: user)
    url = "http://example.com/feed.xml"
    FeedIdentification.create!(
      user: user,
      input: url,
      status: :success,
      candidates: [
        { "profile_key" => "rss", "title" => "Example" }
      ]
    )

    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "select[name='feed[schedule_interval]'] option[value='']", count: 0
    assert_select "select[name='feed[schedule_interval]'] option[selected='selected']" do |options|
      assert_equal Feed::DEFAULT_SCHEDULE_INTERVAL, options.first["value"]
    end
  end

  test "#show should preselect the first active access token with no blank option" do
    sign_in_as(user)
    first_token = create(:access_token, :active, user: user, host: "https://aaa.freefeed.net")
    create(:access_token, :active, user: user, host: "https://zzz.freefeed.net")
    url = "http://example.com/feed.xml"
    FeedIdentification.create!(
      user: user,
      input: url,
      status: :success,
      candidates: [
        { "profile_key" => "rss", "title" => "Example" }
      ]
    )

    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "select[name='feed[access_token_id]'] option[value='']", count: 0
    assert_select "select[name='feed[access_token_id]'] option[selected='selected']" do |options|
      assert_equal first_token.id.to_s, options.first["value"]
    end
  end

  test "#show should replace the access token field with the token prompt when no token exists" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    FeedIdentification.create!(
      user: user,
      input: url,
      status: :success,
      candidates: [
        { "profile_key" => "rss", "title" => "Example" }
      ]
    )

    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    # The prompt stands in for the whole Access Token section, and its submit
    # button disables itself on click to block a double submission.
    assert_select "[data-key='token.gate']", count: 1
    assert_select "button[data-key='token.gate.add'][data-turbo-submits-with]", count: 1
    assert_select "select[name='feed[access_token_id]']", count: 0
    # The group picker can't load groups without a token, so it stays hidden.
    assert_select "#target-group-selector", count: 0
  end

  test "#show should show the group picker once an access token exists" do
    sign_in_as(user)
    create(:access_token, :active, user: user)
    url = "http://example.com/feed.xml"
    FeedIdentification.create!(
      user: user,
      input: url,
      status: :success,
      candidates: [
        { "profile_key" => "rss", "title" => "Example" }
      ]
    )

    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "select[name='feed[access_token_id]']", count: 1
    assert_select "#target-group-selector", count: 1
    assert_select "[data-key='token.gate']", count: 0
  end

  test "#show should write the user's input under params[prompt] for handle inputs" do
    sign_in_as(user)
    handle = "@alice"
    create(
      :feed_identification,
      user: user,
      input: handle,
      started_at: Time.current,
      status: :success,
      candidates: [
        { "profile_key" => "llm", "title" => nil }
      ]
    )

    get feed_identifications_path, params: { url: handle }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "textarea[name='feed[params][prompt]']", text: handle
    refute_includes response.body, 'name="feed[params][url]"'
  end

  test "#show should write the user's input under params[prompt] for free-text queries" do
    sign_in_as(user)
    query = "climate change"
    create(
      :feed_identification,
      user: user,
      input: query,
      started_at: Time.current,
      status: :success,
      candidates: [
        { "profile_key" => "llm", "title" => nil }
      ]
    )

    get feed_identifications_path, params: { url: query }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "textarea[name='feed[params][prompt]']", text: query
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
             params: { url: url },
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
             params: { url: url },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.body, url
  end

  test "#show should render the candidate chooser when multiple candidates work" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    create(
      :feed_identification,
      user: user,
      input: url,
      started_at: Time.current,
      status: :success,
      candidates: [
        { "profile_key" => "rss", "title" => "Example", "test_status" => "passed", "posts_found" => 2 },
        { "profile_key" => "json_feed", "title" => "Example", "test_status" => "passed", "posts_found" => 3 }
      ]
    )

    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, "data-key=\"candidates\""
    assert_includes response.body, "data-key=\"candidate.rss\""
    assert_includes response.body, "data-key=\"candidate.json_feed\""
    # The chooser asks how to fetch; it only switches to the static "Feed type"
    # label once the choice is frozen (edit mode).
    assert_select "label", text: "How should we fetch posts?"
  end

  def success_identification(url, candidates)
    create(:feed_identification, user: user, input: url, started_at: Time.current, status: :success, candidates: candidates)
  end

  def show_chooser(url)
    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  test "#show should show a single working candidate as an annotation, not a chooser" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    success_identification(url, [
      { "profile_key" => "rss", "title" => "Example", "test_status" => "passed", "posts_found" => 3 }
    ])

    show_chooser(url)

    assert_response :success
    assert_select "[data-key='candidates']", count: 0
    assert_select "[data-key='form.feed-type-display']", count: 1
    assert_select "input[type=hidden][name='feed[feed_profile_key]'][value='rss']", count: 1
  end

  test "#show should render the chooser and preselect the suggested candidate for two working candidates" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    success_identification(url, [
      { "profile_key" => "xkcd", "title" => "Example", "test_status" => "passed", "posts_found" => 5 },
      { "profile_key" => "rss", "title" => "Example", "test_status" => "passed", "posts_found" => 3 }
    ])

    show_chooser(url)

    assert_response :success
    assert_select "[data-key='candidates']", count: 1
    assert_select "[data-key='candidate.xkcd.status']", text: "Tested · 5 posts"
    assert_select "input[type=radio][value='xkcd'][checked]"
    assert_select "input[type=radio][disabled]", count: 0
  end

  test "#show should note when a working candidate has no posts yet" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    success_identification(url, [
      { "profile_key" => "rss", "title" => "Example", "test_status" => "passed", "posts_found" => 0 },
      { "profile_key" => "json_feed", "title" => "Example", "test_status" => "passed", "posts_found" => 2 }
    ])

    show_chooser(url)

    assert_response :success
    assert_select "[data-key='candidate.rss.note']", text: /no posts yet/i
  end

  test "#show should drop non-working candidates from the presentation" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    success_identification(url, [
      { "profile_key" => "rss", "title" => "Example", "test_status" => "passed", "posts_found" => 2 },
      { "profile_key" => "xkcd", "title" => "Example", "test_status" => "unreachable" }
    ])

    show_chooser(url)

    assert_response :success
    # One candidate works → annotation; the unreachable one isn't offered.
    assert_select "[data-key='candidates']", count: 0
    assert_select "[data-key='candidate.xkcd']", count: 0
    assert_select "input[type=hidden][name='feed[feed_profile_key]'][value='rss']", count: 1
  end

  test "#show should truncate detected title to Feed::NAME_MAX_LENGTH" do
    sign_in_as(user)
    url = "http://example.com/feed.xml"
    long_title = "A" * (Feed::NAME_MAX_LENGTH + 10)
    FeedIdentification.create!(
      user: user,
      input: url,
      status: :success,
      candidates: [
        { "profile_key" => "rss", "title" => long_title }
      ]
    )

    get feed_identifications_path, params: { url: url }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "input[name='feed[name]'][value='#{"A" * (Feed::NAME_MAX_LENGTH - 1)}…']", count: 1
  end

  test "#show should re-render the edit form for a feed-scoped source re-detection" do
    sign_in_as(user)
    feed = create(:feed, user: user, feed_profile_key: "rss", params: { "url" => "http://example.com/old.xml" })
    new_url = "http://example.com/new.xml"
    create(:feed_identification, user: user, input: new_url, status: :success, started_at: Time.current,
           candidates: [{ "profile_key" => "rss", "test_status" => "passed", "title" => "New" }])

    get feed_identifications_path, params: { url: new_url, feed_id: feed.id },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "input[data-key='form.source-edit'][value=?]", new_url
    assert_select "form[action=?]", feed_path(feed)
    assert_select "input[type=hidden][name='_method'][value='patch']"
  end

  test "#show should warn about repeats and offer the threshold for a same-profile source change" do
    sign_in_as(user)
    feed = create(:feed, user: user, feed_profile_key: "rss", params: { "url" => "http://example.com/old.xml" })
    new_url = "http://example.com/new.xml"
    create(:feed_identification, user: user, input: new_url, status: :success, started_at: Time.current,
           candidates: [{ "profile_key" => "rss", "test_status" => "passed", "title" => "New" }])

    get feed_identifications_path, params: { url: new_url, feed_id: feed.id },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "[data-key='form.dup-risk-warning']"
    assert_select "input[data-key='form.import-after-enabled'][checked]", count: 0
  end

  test "#show should default the threshold on when re-detection changes the profile" do
    sign_in_as(user)
    feed = create(:feed, user: user, feed_profile_key: "rss", params: { "url" => "http://example.com/old.xml" })
    new_url = "https://xkcd.com/rss.xml"
    create(:feed_identification, user: user, input: new_url, status: :success, started_at: Time.current,
           candidates: [{ "profile_key" => "xkcd", "test_status" => "passed", "title" => "xkcd" }])

    get feed_identifications_path, params: { url: new_url, feed_id: feed.id },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "[data-key='form.dup-risk-warning']"
    assert_select "input[data-key='form.import-after-enabled'][checked]"
  end

  test "#show should re-render the edit form without an AI mode when edit re-detection finds no feed" do
    sign_in_as(user)
    feed = create(:feed, user: user, feed_profile_key: "rss", params: { "url" => "http://example.com/old.xml" })
    new_url = "http://example.com/none.xml"
    create(:feed_identification, user: user, input: new_url, status: :success, started_at: Time.current,
           candidates: [{ "profile_key" => "rss", "test_status" => "failed" }])

    get feed_identifications_path, params: { url: new_url, feed_id: feed.id },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    # The engine is fixed in edit (spec §4): the edit form comes back with the
    # attempted URL and the hint, and no AI mode is on offer.
    assert_select "form[action=?]", feed_path(feed)
    assert_select "input[data-key='form.source-edit'][value=?]", new_url
    assert_select "[data-key='form.source-error']", text: /pull any posts/
    assert_select "[data-key='entry.mode-ai']", count: 0
  end

  test "#show should keep re-detection in the edit context on a couldn't-reach result" do
    sign_in_as(user)
    feed = create(:feed, user: user, feed_profile_key: "rss", params: { "url" => "http://example.com/old.xml" })
    new_url = "http://example.com/down.xml"
    create(:feed_identification, user: user, input: new_url, status: :success, started_at: Time.current,
           error: "unreachable", candidates: [])

    get feed_identifications_path, params: { url: new_url, feed_id: feed.id },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    # Saving again with the preserved URL re-runs detection, so the edit form
    # itself is the retry state.
    assert_select "form[action=?]", feed_path(feed)
    assert_select "input[data-key='form.source-edit'][value=?]", new_url
    assert_select "[data-key='form.source-error']", text: /couldn't reach that link/i
    assert_select "[data-key='entry.mode-ai']", count: 0
  end

  private
end
