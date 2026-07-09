require "test_helper"

# Edit semantics: operational fields edit freely; a deterministic feed's source
# re-runs detection before saving. An AI feed's prompt is its source and the uid
# scheme never changes, so it stays editable throughout — draft or live (spec §4).
class SmartFeedCreationEditTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def feed
    @feed ||= create(:feed,
                     user: user,
                     access_token: access_token,
                     state: :enabled,
                     target_group: "testgroup",
                     feed_profile_key: "rss",
                     params: { "url" => "http://example.com/feed.xml" })
  end

  def draft_ai_feed
    @draft_ai_feed ||= create(:feed,
                              user: user,
                              state: :draft,
                              feed_profile_key: "llm",
                              params: { "prompt" => "follow the A24 blog" })
  end

  test "#patch should accept an operational-only edit on an enabled feed without re-running detection" do
    sign_in_as(user)
    feed

    assert_no_enqueued_jobs do
      patch feed_url(feed), params: { feed: { name: "Renamed" }, enable_feed: "1" }
    end

    assert_redirected_to feed_path(feed)
    feed.reload
    assert_equal "Renamed", feed.name
    assert_equal "enabled", feed.state
  end

  test "#patch should ignore attempts to mass-assign url through the edit form" do
    sign_in_as(user)
    original_url = feed.url

    patch feed_url(feed), params: {
      feed: {
        url: "http://attacker.example/feed.xml",
        name: "Renamed"
      }
    }

    assert_redirected_to feed_path(feed)
    feed.reload
    assert_equal original_url, feed.url
    assert_equal "Renamed", feed.name
  end

  test "#patch should route a source change through detection instead of writing params directly" do
    sign_in_as(user)
    original_params = feed.params

    assert_enqueued_with(job: FeedIdentificationJob) do
      patch feed_url(feed), params: {
        feed: {
          params: { url: "http://attacker.example/feed.xml" },
          name: "Renamed"
        }
      }
    end

    feed.reload
    assert_equal original_params, feed.params, "the source isn't written until detection confirms it"
    assert_equal "Renamed", feed.name
  end

  test "#patch should hold the source and re-detect when a live feed's URL changes" do
    sign_in_as(user)

    assert_enqueued_with(job: FeedIdentificationJob) do
      patch feed_url(feed), params: { feed: { params: { url: "http://example.com/other.xml" }, name: "Renamed" } },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_select "[data-controller*='polling'][data-polling-endpoint-value*=?]", "feed_id=#{feed.id}"
    feed.reload
    assert_equal "http://example.com/feed.xml", feed.url
    assert_equal "Renamed", feed.name
  end

  test "#patch should apply a re-detected source once a working candidate confirms it" do
    sign_in_as(user)
    new_url = "http://example.com/other.xml"
    create(:feed_identification, user: user, input: new_url, status: :success, started_at: Time.current,
           candidates: [{ "profile_key" => "rss", "test_status" => "passed", "title" => "Other" }])

    patch feed_url(feed), params: { feed: { params: { url: new_url }, feed_profile_key: "rss" }, enable_feed: "1" }

    assert_redirected_to feed_path(feed)
    feed.reload
    assert_equal new_url, feed.url
    assert_equal "enabled", feed.state
  end

  test "#patch should enable a disabled feed when confirming a re-detected source with Enable ticked" do
    sign_in_as(user)
    disabled = create(:feed, user: user, access_token: access_token, state: :disabled,
                             target_group: "testgroup", feed_profile_key: "rss",
                             params: { "url" => "http://example.com/feed.xml" })
    new_url = "http://example.com/other.xml"
    create(:feed_identification, user: user, input: new_url, status: :success, started_at: Time.current,
           candidates: [{ "profile_key" => "rss", "test_status" => "passed", "title" => "Other" }])

    patch feed_url(disabled), params: { feed: { params: { url: new_url }, feed_profile_key: "rss" }, enable_feed: "1" }

    assert_redirected_to feed_path(disabled)
    disabled.reload
    assert_equal new_url, disabled.url
    assert_equal "enabled", disabled.state
  end

  test "#patch should re-detect rather than confirm a profile that isn't a working candidate" do
    sign_in_as(user)
    new_url = "http://example.com/other.xml"
    create(:feed_identification, user: user, input: new_url, status: :success, started_at: Time.current,
           candidates: [{ "profile_key" => "rss", "test_status" => "passed", "title" => "Other" }])

    assert_enqueued_with(job: FeedIdentificationJob) do
      patch feed_url(feed), params: { feed: { params: { url: new_url }, feed_profile_key: "xkcd" } }
    end

    feed.reload
    assert_equal "http://example.com/feed.xml", feed.url
  end

  test "#patch should ignore attempts to mass-assign the feed_profile_key" do
    sign_in_as(user)
    original_profile = feed.feed_profile_key

    patch feed_url(feed), params: {
      feed: {
        feed_profile_key: "xkcd",
        name: "Renamed"
      }
    }

    feed.reload
    assert_equal original_profile, feed.feed_profile_key
  end

  test "#edit should let a draft AI feed's prompt be edited" do
    sign_in_as(user)

    get edit_feed_url(draft_ai_feed)

    assert_response :success
    assert_select "textarea[name='feed[params][prompt]']", text: "follow the A24 blog"
    assert_select "[data-key='form.source-locked-note']", count: 0
  end

  test "#patch should update a draft AI feed's prompt" do
    sign_in_as(user)

    patch feed_url(draft_ai_feed), params: { feed: { params: { prompt: "follow Pitchfork reviews" } } }

    assert_redirected_to feed_path(draft_ai_feed)
    draft_ai_feed.reload
    assert_equal "follow Pitchfork reviews", draft_ai_feed.params["prompt"]
  end

  def enabled_ai_feed
    @enabled_ai_feed ||= begin
      credential = create(:ai_credential, :active, user: user,
                                                   available_models: [{ "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" }])
      create(:feed, user: user, access_token: access_token, state: :enabled,
                    target_group: "testgroup", feed_profile_key: "llm",
                    params: { "prompt" => "follow the A24 blog" },
                    ai_credential: credential, ai_model: "claude-sonnet-4-6")
    end
  end

  test "#edit should keep a live AI feed's prompt editable with a backfill note" do
    sign_in_as(user)

    get edit_feed_url(enabled_ai_feed)

    assert_response :success
    assert_select "textarea[name='feed[params][prompt]']", text: "follow the A24 blog"
    assert_select "[data-key='form.prompt-backfill-note']"
    assert_select "[data-key='form.source-locked-note']", count: 0
  end

  test "#patch should update a live AI feed's prompt" do
    sign_in_as(user)

    patch feed_url(enabled_ai_feed), params: { feed: { params: { prompt: "follow Pitchfork reviews" }, name: enabled_ai_feed.name }, enable_feed: "1" }

    assert_redirected_to feed_path(enabled_ai_feed)
    enabled_ai_feed.reload
    assert_equal "follow Pitchfork reviews", enabled_ai_feed.params["prompt"]
    assert_equal "enabled", enabled_ai_feed.state
  end
end
