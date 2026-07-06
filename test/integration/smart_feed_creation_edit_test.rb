require "test_helper"

# Edit semantics: operational fields edit freely; a deterministic feed's source
# and profile stay anchored after creation. An AI feed's prompt carries no
# duplicate risk, so it stays editable while the feed is a draft (spec §4).
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

  test "#patch should ignore attempts to mass-assign the params jsonb" do
    sign_in_as(user)
    original_params = feed.params

    patch feed_url(feed), params: {
      feed: {
        params: { url: "http://attacker.example/feed.xml" },
        name: "Renamed"
      }
    }

    feed.reload
    assert_equal original_params, feed.params
    assert_equal "Renamed", feed.name
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

  test "#edit should keep an enabled AI feed's prompt read-only" do
    sign_in_as(user)
    credential = create(:ai_credential, :active, user: user,
                                                 available_models: [{ "id" => "claude-sonnet-4-6", "name" => "Claude Sonnet 4.6" }])
    enabled_ai = create(:feed, user: user, access_token: access_token, state: :enabled,
                               target_group: "testgroup", feed_profile_key: "llm",
                               params: { "prompt" => "follow the A24 blog" },
                               ai_credential: credential, ai_model: "claude-sonnet-4-6")

    get edit_feed_url(enabled_ai)

    assert_response :success
    assert_select "textarea[name='feed[params][prompt]']", count: 0
    assert_select "[data-key='form.source-display']"
  end
end
