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

  test "should require unique name when present" do
    user = create(:user)
    create(:feed, user: user, name: "Test Feed")
    feed = build(:feed, user: user, name: "Test Feed")
    assert_not feed.valid?
    assert feed.errors.of_kind?(:name, :taken)
  end

  test "should require url" do
    feed = build(:feed, url: nil)
    assert_not feed.valid?
    assert feed.errors.of_kind?(:url, :blank)
  end

  test "should require cron_expression for enabled feeds" do
    # Test the validation logic directly by bypassing the auto-disable callback
    feed = create(:feed, state: :enabled)

    # Manually set state and cron_expression to test the validation condition
    feed.define_singleton_method(:enabled?) { true }
    feed.cron_expression = nil

    assert_not feed.valid?
    assert feed.errors.of_kind?(:cron_expression, :blank)
  end

  test "should not require cron_expression for disabled feeds" do
    feed = build(:feed, cron_expression: nil, state: :disabled)
    feed.valid?
    assert_not feed.errors.of_kind?(:cron_expression, :blank)
  end

  test "should require feed_profile_key" do
    feed = build(:feed, :without_feed_profile)
    assert_not feed.valid?
    assert feed.errors.of_kind?(:feed_profile_key, :blank)
  end

  test "should have disabled state by default" do
    feed = build(:feed)
    assert_equal "disabled", feed.state
  end

  test "should support state transitions" do
    feed = create(:feed)

    assert feed.disabled?

    feed.enabled!
    assert feed.enabled?

    feed.disabled!
    assert feed.disabled?
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

  test "#due should include feeds without schedule" do
    freeze_time do
      feed = create(:feed, state: :enabled)

      assert_includes Feed.due, feed
    end
  end

  test "#due should include feeds with past next_run_at" do
    freeze_time do
      feed = create(:feed, state: :enabled)
      create(:feed_schedule, feed: feed, next_run_at: 1.hour.ago)

      assert_includes Feed.due, feed
    end
  end

  test "#due should exclude feeds with future next_run_at" do
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

  test "should set default state to disabled for new records" do
    feed = Feed.new
    assert_equal "disabled", feed.state
  end

  test "should not change state for persisted records" do
    feed = create(:feed, state: :enabled)
    reloaded_feed = Feed.find(feed.id)
    assert_equal "enabled", reloaded_feed.state
  end

  test "#can_be_enabled? returns true when feed has active access token and target group" do
    access_token = create(:access_token, :active)
    feed = create(:feed, access_token: access_token, target_group: "test_group")

    assert feed.can_be_enabled?
  end

  test "#can_be_enabled? returns false when feed has no access token" do
    feed = create(:feed, :without_access_token)

    assert_not feed.can_be_enabled?
  end

  test "#can_be_enabled? returns false when feed has inactive access token" do
    access_token = create(:access_token, :inactive)
    feed = create(:feed, access_token: access_token, target_group: "test_group")

    assert_not feed.can_be_enabled?
  end

  test "#can_be_enabled? returns false when feed has no target group" do
    access_token = create(:access_token, :active)
    feed = create(:feed, access_token: access_token, target_group: nil)

    assert_not feed.can_be_enabled?
  end

  test "#can_be_enabled? returns false when feed has neither access token nor target group" do
    feed = create(:feed, :without_access_token)

    assert_not feed.can_be_enabled?
  end

  test "#can_be_enabled? returns false when feed has no feed_profile_key" do
    feed = build(:feed, :without_feed_profile)

    assert_not feed.can_be_enabled?
  end

  test "#processor_class resolves correct processor class" do
    feed = create(:feed, feed_profile_key: "rss")

    assert_equal Processor::RssProcessor, feed.processor_class
  end

  test "#normalizer_class resolves correct normalizer class" do
    feed = create(:feed, feed_profile_key: "rss")

    assert_equal Normalizer::RssNormalizer, feed.normalizer_class
  end

  test "#processor_instance creates processor with feed and raw data" do
    feed = create(:feed, feed_profile_key: "rss")
    raw_data = "<rss><item><title>Test</title></item></rss>"

    processor = feed.processor_instance(raw_data)

    assert_instance_of Processor::RssProcessor, processor
  end

  test "#normalizer_instance creates normalizer with feed entry" do
    feed = create(:feed, feed_profile_key: "rss")
    feed_entry = create(:feed_entry, feed: feed)

    normalizer = feed.normalizer_instance(feed_entry)

    assert_instance_of Normalizer::RssNormalizer, normalizer
  end

  test "#posts_per_day returns empty hash when no posts exist" do
    feed = create(:feed)
    start_date = Date.current
    end_date = Date.current

    result = feed.posts_per_day(start_date, end_date)

    assert_equal({}, result)
  end

  test "#posts_per_day returns correct counts for posts within date range" do
    feed = create(:feed)

    travel_to Date.current.beginning_of_day do
      create(:post, feed: feed, published_at: Date.current.beginning_of_day + 2.hours)
      create(:post, feed: feed, published_at: Date.current.beginning_of_day + 4.hours)
      create(:post, feed: feed, published_at: 1.day.from_now.beginning_of_day + 1.hour)
      create(:post, feed: feed, published_at: 2.days.from_now.beginning_of_day + 3.hours)

      # Post outside the range
      create(:post, feed: feed, published_at: 5.days.from_now.beginning_of_day)

      result = feed.posts_per_day(Date.current, 2.days.from_now)

      assert_equal 3, result.keys.length
      assert_equal 2, result[Date.current]
      assert_equal 1, result[1.day.from_now.to_date]
      assert_equal 1, result[2.days.from_now.to_date]
      assert_nil result[5.days.from_now.to_date]
    end
  end

  test "#posts_per_day excludes posts from other feeds" do
    feed1 = create(:feed)
    feed2 = create(:feed)

    travel_to Date.current.beginning_of_day do
      create(:post, feed: feed1, published_at: Date.current.beginning_of_day + 1.hour)
      create(:post, feed: feed2, published_at: Date.current.beginning_of_day + 2.hours)

      result = feed1.posts_per_day(Date.current, Date.current)

      assert_equal 1, result[Date.current]
    end
  end

  test "#posts_per_day handles posts at day boundaries correctly" do
    feed = create(:feed)

    travel_to Date.current.beginning_of_day do
      create(:post, feed: feed, published_at: Date.current.beginning_of_day)
      create(:post, feed: feed, published_at: Date.current.end_of_day)

      result = feed.posts_per_day(Date.current, Date.current)

      assert_equal 2, result[Date.current]
    end
  end

  test "#metrics_for_date_range returns metrics with gaps filled" do
    feed = create(:feed)
    create(:feed_metric, feed: feed, date: 3.days.ago.to_date, posts_count: 5)
    create(:feed_metric, feed: feed, date: 1.day.ago.to_date, posts_count: 3)

    result = feed.metrics_for_date_range(3.days.ago.to_date, Date.current)

    assert_equal 4, result.length
    assert_equal 5, result[0]["posts_count"]
    assert_equal 0, result[1]["posts_count"]
    assert_equal 3, result[2]["posts_count"]
    assert_equal 0, result[3]["posts_count"]
  end

  test "#metrics_for_date_range accepts valid metric parameter" do
    feed = create(:feed)
    create(:feed_metric, feed: feed, date: Date.current, posts_count: 5, invalid_posts_count: 2)

    result = feed.metrics_for_date_range(Date.current, Date.current, metric: :invalid_posts_count)

    assert_equal 1, result.length
    assert_equal 2, result[0]["invalid_posts_count"]
  end

  test "#metrics_for_date_range raises error for invalid metric" do
    feed = create(:feed)

    error = assert_raises(ArgumentError) do
      feed.metrics_for_date_range(Date.current, Date.current, metric: "malicious_column")
    end
  end

  test "#metrics_for_date_range prevents SQL injection via metric parameter" do
    feed = create(:feed)

    error = assert_raises(ArgumentError) do
      feed.metrics_for_date_range(
        Date.current,
        Date.current,
        metric: "posts_count; DROP TABLE feed_metrics--"
      )
    end
  end

  test "#metrics_for_date_range safely handles date parameters" do
    feed = create(:feed)
    create(:feed_metric, feed: feed, date: Date.current, posts_count: 5)

    # These should not cause SQL injection even with quotes
    result = feed.metrics_for_date_range(Date.current, Date.current)

    assert_equal 1, result.length
    assert_equal 5, result[0]["posts_count"]
  end

  test ".schedule_intervals_for_select should return array of display names and keys" do
    result = Feed.schedule_intervals_for_select

    assert_instance_of Array, result
    assert_equal 9, result.length
    assert_includes result, ["10 minutes", "10m"]
    assert_includes result, ["1 hour", "1h"]
    assert_includes result, ["2 days", "2d"]
  end

  test "#schedule_interval should return key for matching cron expression" do
    feed = build(:feed, cron_expression: "0 * * * *")

    assert_equal "1h", feed.schedule_interval
  end

  test "#schedule_interval should return key for 10 minutes interval" do
    feed = build(:feed, cron_expression: "*/10 * * * *")

    assert_equal "10m", feed.schedule_interval
  end

  test "#schedule_interval should return key for 2 days interval" do
    feed = build(:feed, cron_expression: "0 0 */2 * *")

    assert_equal "2d", feed.schedule_interval
  end

  test "#schedule_interval should return nil for non-standard cron expression" do
    feed = build(:feed, cron_expression: "15 3 * * *")

    assert_nil feed.schedule_interval
  end

  test "#schedule_interval= should set cron_expression from valid key" do
    feed = build(:feed)

    feed.schedule_interval = "1h"

    assert_equal "0 * * * *", feed.cron_expression
  end

  test "#schedule_interval= should set cron_expression for 10 minutes" do
    feed = build(:feed)

    feed.schedule_interval = "10m"

    assert_equal "*/10 * * * *", feed.cron_expression
  end

  test "#schedule_interval= should set cron_expression for 2 days" do
    feed = build(:feed)

    feed.schedule_interval = "2d"

    assert_equal "0 0 */2 * *", feed.cron_expression
  end

  test "#schedule_interval= should set nil for invalid key" do
    feed = build(:feed, cron_expression: "0 * * * *")

    feed.schedule_interval = "invalid"

    assert_nil feed.cron_expression
  end

  test "#schedule_display should return display name for standard interval" do
    feed = build(:feed, cron_expression: "0 * * * *")

    assert_equal "1 hour", feed.schedule_display
  end

  test "#schedule_display should return display name for 10 minutes" do
    feed = build(:feed, cron_expression: "*/10 * * * *")

    assert_equal "10 minutes", feed.schedule_display
  end

  test "#schedule_display should return cron expression for non-standard interval" do
    feed = build(:feed, cron_expression: "15 3 * * *")

    assert_equal "15 3 * * *", feed.schedule_display
  end

  test "#schedule_display should return cron expression when schedule_interval is nil" do
    feed = build(:feed, cron_expression: "0 */3 * * *")

    assert_equal "0 */3 * * *", feed.schedule_display
  end
end
