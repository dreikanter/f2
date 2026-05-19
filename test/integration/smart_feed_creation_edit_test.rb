require "test_helper"

# FR-026 / FR-027 / FR-028 edit semantics: operational fields can be
# edited freely; source-side fields stay anchored after creation.
# Updates never re-run detection or preview because the create-time
# detection is authoritative (the form keeps the URL and profile key
# read-only on edit).
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

  test "#patch should accept an operational-only edit on an enabled feed without re-running detection" do
    sign_in_as(user)
    feed

    assert_no_enqueued_jobs do
      patch feed_url(feed), params: { feed: { name: "Renamed" } }
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
end
