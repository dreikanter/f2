require "test_helper"

class FeedTest < ActiveSupport::TestCase
  test "should be valid with all required attributes" do
    feed = build(:feed)
    assert feed.valid?
  end

  test "should require name" do
    feed = build(:feed, name: nil)
    assert_not feed.valid?
    assert feed.errors.of_kind?(:name, :blank)
  end

  test "should require url" do
    feed = build(:feed, url: nil)
    assert_not feed.valid?
    assert feed.errors.of_kind?(:url, :blank)
  end

  test "should require cron_expression" do
    feed = build(:feed, cron_expression: nil)
    assert_not feed.valid?
    assert feed.errors.of_kind?(:cron_expression, :blank)
  end

  test "should require loader" do
    feed = build(:feed, loader: nil)
    assert_not feed.valid?
    assert feed.errors.of_kind?(:loader, :blank)
  end

  test "should require processor" do
    feed = build(:feed, processor: nil)
    assert_not feed.valid?
    assert feed.errors.of_kind?(:processor, :blank)
  end

  test "should require normalizer" do
    feed = build(:feed, normalizer: nil)
    assert_not feed.valid?
    assert feed.errors.of_kind?(:normalizer, :blank)
  end

  test "should have enabled state by default" do
    feed = build(:feed)
    assert_equal "enabled", feed.state
  end

  test "should support state transitions" do
    feed = create(:feed)

    feed.paused!
    assert feed.paused?

    feed.disabled!
    assert feed.disabled?

    feed.enabled!
    assert feed.enabled?
  end

  test "should have empty description by default" do
    feed = build(:feed)
    assert_equal "", feed.description
  end

  test "should destroy associated feed_schedule when destroyed" do
    feed = create(:feed, :with_schedule)

    assert_difference("FeedSchedule.count", -1) do
      feed.destroy!
    end
  end

  test "due scope should include feeds without schedule" do
    freeze_time do
      feed = create(:feed)

      assert_includes Feed.due, feed
    end
  end

  test "due scope should include feeds with past next_run_at" do
    freeze_time do
      feed = create(:feed)
      create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)

      assert_includes Feed.due, feed
    end
  end

  test "due scope should exclude feeds with future next_run_at" do
    freeze_time do
      feed = create(:feed)
      create(:feed_schedule, feed: feed, next_run_at: 1.hour.from_now)

      assert_not_includes Feed.due, feed
    end
  end

  test "should require user" do
    feed = build(:feed, user: nil)
    assert_not feed.valid?
    assert feed.errors.of_kind?(:user, :blank)
  end

  test "should validate name length" do
    feed = build(:feed, name: "a" * 41)
    assert_not feed.valid?
    assert feed.errors.of_kind?(:name, :too_long)

    feed = build(:feed, name: "Valid Name With Spaces")
    assert feed.valid?
  end

  test "should validate url format" do
    feed = build(:feed, url: "not-a-url")
    assert_not feed.valid?
    assert feed.errors.of_kind?(:url, :invalid)

    feed = build(:feed, url: "ftp://example.com")
    assert_not feed.valid?
    assert feed.errors.of_kind?(:url, :invalid)

    feed = build(:feed, url: "https://example.com/feed.xml")
    assert feed.valid?
  end

  test "should validate cron expression format" do
    feed = build(:feed, cron_expression: "invalid cron")
    assert_not feed.valid?
    assert_includes feed.errors[:cron_expression].first, "is not a valid cron expression"

    feed = build(:feed, cron_expression: "0 * * * *")
    assert feed.valid?
  end

  test "should normalize name by stripping spaces" do
    feed = create(:feed, name: "  Test-Feed  ")
    assert_equal "Test-Feed", feed.name
  end

  test "should normalize url by stripping spaces" do
    feed = create(:feed, url: "  https://example.com/feed.xml  ")
    assert_equal "https://example.com/feed.xml", feed.url
  end

  test "should normalize cron expression by stripping spaces" do
    feed = create(:feed, cron_expression: "  0 * * * *  ")
    assert_equal "0 * * * *", feed.cron_expression
  end

  test "should normalize description by removing line breaks" do
    feed = create(:feed, description: "Line 1\nLine 2\r\nLine 3")
    assert_equal "Line 1 Line 2 Line 3", feed.description
  end

  test "should enforce unique name per user" do
    user = create(:user)
    create(:feed, user: user, name: "duplicate")

    duplicate_feed = build(:feed, user: user, name: "duplicate")
    assert_not duplicate_feed.valid?
    assert duplicate_feed.errors.of_kind?(:name, :taken)
  end

  test "should allow same name for different users" do
    user1 = create(:user)
    user2 = create(:user)
    create(:feed, user: user1, name: "same-name")

    feed2 = build(:feed, user: user2, name: "same-name")
    assert feed2.valid?
  end

  test "should set default state to enabled for new records" do
    feed = Feed.new
    assert_equal "enabled", feed.state
  end

  test "should not change state for persisted records" do
    feed = create(:feed, state: :paused)
    reloaded_feed = Feed.find(feed.id)
    assert_equal "paused", reloaded_feed.state
  end

  test "should require access token for enabled feeds" do
    feed = build(:feed, :without_access_token, state: :enabled)
    assert_not feed.valid?
    assert_includes feed.errors[:access_token], "can't be blank"
  end

  test "should allow disabled feeds without access token" do
    user = create(:user)
    feed = build(:feed, :without_access_token, state: :disabled, user: user)
    assert feed.valid?
  end

  test "should allow paused feeds without access token" do
    user = create(:user)
    feed = build(:feed, :without_access_token, state: :paused, user: user)
    assert feed.valid?
  end

  test "should allow updating existing feed to disabled with nil access token" do
    feed = create(:feed)
    assert feed.update!(state: :disabled, access_token: nil)
    assert_equal "disabled", feed.state
    assert_nil feed.access_token
  end
end
