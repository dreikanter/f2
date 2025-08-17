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
end
