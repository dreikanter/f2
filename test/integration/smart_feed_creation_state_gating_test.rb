require "test_helper"

# FR-012 + FR-013 state gating: the controller uses a save-then-promote flow:
# the initial save persists the feed as a draft (new records default to :draft),
# then `Feed#enable` attempts the promotion under the `:enable` validation context.
# Previewing is optional — a feed can be enabled with or without a recent preview.
class SmartFeedCreationStateGatingTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def feed_params
    feed_attrs = {
      params: { url: "http://example.com/feed.xml" },
      name: "Example",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h"
    }
    {
      feed: feed_attrs,
      enable_feed: "1"
    }
  end

  def seed_preview(params: { "url" => "http://example.com/feed.xml" }, ready_at: Time.current)
    create(:feed_preview, :completed, user: user, feed_profile_key: "rss",
           params: params, ready_at: ready_at)
  end

  test "#post should land in enabled state with a fresh ready preview" do
    sign_in_as(user)
    seed_preview

    assert_difference("Feed.count", 1) do
      post feeds_path, params: feed_params
    end

    assert_equal "enabled", Feed.last.state
  end

  test "#post should enable a feed when no preview exists" do
    sign_in_as(user)

    assert_difference("Feed.count", 1) do
      post feeds_path, params: feed_params
    end

    assert_equal "enabled", Feed.last.state
  end

  test "#post should enable a feed even when the only preview is stale" do
    sign_in_as(user)
    seed_preview(ready_at: 2.hours.ago)

    assert_difference("Feed.count", 1) do
      post feeds_path, params: feed_params
    end

    assert_equal "enabled", Feed.last.state
  end

  test "#post should enable a feed even when the only preview is for different params" do
    sign_in_as(user)
    seed_preview(params: { "url" => "http://different.com/feed.xml" })

    post feeds_path, params: feed_params

    assert_equal "enabled", Feed.last.state
  end
end
