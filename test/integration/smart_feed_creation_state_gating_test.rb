require "test_helper"

# FR-012 + FR-013 state gating: promoting a feed to enabled requires a
# fresh preview_token tied to (user, profile, params). The controller uses
# a save-then-promote flow: the initial save persists the feed as a draft
# (new records default to :draft), then `Feed#enable` attempts the
# promotion under the `:enable` validation context. A missing or invalid
# token keeps the feed at :draft and re-renders the form with errors.
class SmartFeedCreationStateGatingTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def feed_params(preview_token: nil)
    feed_attrs = {
      url: "http://example.com/feed.xml",
      name: "Example",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h"
    }
    {
      feed: feed_attrs,
      enable_feed: "1",
      preview_token: preview_token
    }
  end

  def valid_preview_token
    PreviewToken.sign(
      user_id: user.id,
      profile_key: "rss",
      params: { "url" => "http://example.com/feed.xml" },
      generated_at: Time.current
    )
  end

  test "#post should land in enabled state with a valid preview token" do
    sign_in_as(user)

    assert_difference("Feed.count", 1) do
      post feeds_path, params: feed_params(preview_token: valid_preview_token)
    end

    assert_equal "enabled", Feed.last.state
  end

  test "#post should fall back to draft when no preview token is supplied" do
    sign_in_as(user)

    assert_difference("Feed.count", 1) do
      post feeds_path, params: feed_params(preview_token: nil)
    end

    assert_equal "draft", Feed.last.state
  end

  test "#post should reject a tampered preview token and fall back to draft" do
    sign_in_as(user)
    tampered = valid_preview_token.split(".").first + ".not-a-real-signature"

    assert_difference("Feed.count", 1) do
      post feeds_path, params: feed_params(preview_token: tampered)
    end

    assert_equal "draft", Feed.last.state
  end

  test "#post should reject an expired preview token and fall back to draft" do
    sign_in_as(user)

    expired = PreviewToken.sign(
      user_id: user.id,
      profile_key: "rss",
      params: { "url" => "http://example.com/feed.xml" },
      generated_at: 2.hours.ago
    )

    assert_difference("Feed.count", 1) do
      post feeds_path, params: feed_params(preview_token: expired)
    end

    assert_equal "draft", Feed.last.state
  end

  test "#post should reject a preview token for different params and fall back to draft" do
    sign_in_as(user)

    mismatched_token = PreviewToken.sign(
      user_id: user.id,
      profile_key: "rss",
      params: { "url" => "http://different.com/feed.xml" },
      generated_at: Time.current
    )

    post feeds_path, params: feed_params(preview_token: mismatched_token)

    assert_equal "draft", Feed.last.state
  end
end
