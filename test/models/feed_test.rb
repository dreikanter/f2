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

  test "should default params to empty hash for new records" do
    feed = Feed.new
    assert_equal({}, feed.params)
  end

  test "#url should return params['url']" do
    feed = build(:feed, params: { "url" => "https://example.com/feed.xml" })
    assert_equal "https://example.com/feed.xml", feed.url
  end

  test "#url should return nil when params has no url" do
    feed = build(:feed, params: {})
    assert_nil feed.url
  end

  test "#url= should write into params['url']" do
    feed = build(:feed, params: { "extra" => "value" })
    feed.url = "https://example.com/new.xml"

    assert_equal "https://example.com/new.xml", feed.params["url"]
    assert_equal "value", feed.params["extra"], "should preserve existing params"
  end

  test "#url= should strip whitespace from string values" do
    feed = build(:feed)
    feed.url = "  https://example.com/feed.xml  "

    assert_equal "https://example.com/feed.xml", feed.url
  end

  test "#url= should remove the url key when assigned nil" do
    feed = build(:feed, params: { "url" => "https://example.com/feed.xml", "extra" => "value" })
    feed.url = nil

    assert_nil feed.url
    assert_not feed.params.key?("url")
    assert_equal "value", feed.params["extra"]
  end

  test "should reject params missing required keys per profile schema" do
    feed = build(:feed, feed_profile_key: "rss", params: {})
    assert_not feed.valid?
    assert feed.errors.of_kind?(:params, "object at root is missing required properties: url")
  end

  test "should reject params with malformed url per profile schema" do
    feed = build(:feed, feed_profile_key: "rss", params: { "url" => "not-a-uri" })
    assert_not feed.valid?
    assert feed.errors[:params].any? { |msg| msg.include?("/url") && msg.include?("uri") },
           "expected a /url + uri error, got: #{feed.errors[:params].inspect}"
  end

  test "should accept params matching profile schema" do
    feed = build(:feed, feed_profile_key: "rss", params: { "url" => "https://example.com/feed.xml" })
    feed.valid?
    assert_empty feed.errors[:params]
  end

  test "should skip params schema validation when feed_profile_key is unknown" do
    feed = build(:feed, feed_profile_key: "nonexistent", params: { "anything" => 1 })
    feed.valid?
    assert_empty feed.errors[:params]
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

    feed.preview_token = PreviewToken.sign(
      user_id: feed.user_id,
      profile_key: feed.feed_profile_key,
      params: feed.params,
      generated_at: Time.current
    )
    feed.enabled!
    assert feed.enabled?

    feed.disabled!
    assert feed.disabled?
  end

  test "should create feed_schedule when transitioning from disabled to enabled" do
    user = create(:user)
    access_token = create(:access_token, :active, user: user)
    feed = create(:feed, user: user, state: :disabled, access_token: access_token, target_group: "testgroup", cron_expression: "0 * * * *")

    assert_nil feed.feed_schedule

    feed.preview_token = PreviewToken.sign(
      user_id: feed.user_id,
      profile_key: feed.feed_profile_key,
      params: feed.params,
      generated_at: Time.current
    )
    feed.update!(state: :enabled)

    schedule = feed.reload.feed_schedule
    assert_not_nil schedule
    assert_not_nil schedule.next_run_at
    assert_not_nil schedule.last_run_at
  end

  test "should not create duplicate feed_schedule when already exists" do
    user = create(:user)
    access_token = create(:access_token, :active, user: user)
    feed = create(:feed, :with_schedule, user: user, state: :disabled, access_token: access_token, target_group: "testgroup")

    existing_schedule = feed.feed_schedule

    feed.preview_token = PreviewToken.sign(
      user_id: feed.user_id,
      profile_key: feed.feed_profile_key,
      params: feed.params,
      generated_at: Time.current
    )
    feed.update!(state: :enabled)

    assert_equal existing_schedule.id, feed.reload.feed_schedule.id
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
    user = create(:user)
    access_token = create(:access_token, :active, user: user)
    feed = create(:feed, user: user, access_token: access_token, target_group: "test_group")

    assert feed.can_be_enabled?
  end

  test "#can_be_enabled? returns false when feed has no access token" do
    feed = create(:feed, :without_access_token)

    assert_not feed.can_be_enabled?
  end

  test "#can_be_enabled? returns false when feed has inactive access token" do
    user = create(:user)
    access_token = create(:access_token, :inactive, user: user)
    feed = create(:feed, user: user, access_token: access_token, target_group: "test_group")

    assert_not feed.can_be_enabled?
  end

  test "#can_be_enabled? returns false when feed has no target group" do
    user = create(:user)
    access_token = create(:access_token, :active, user: user)
    feed = create(:feed, user: user, access_token: access_token, target_group: nil)

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

    expected = [
      ["10 minutes", "10m"],
      ["20 minutes", "20m"],
      ["30 minutes", "30m"],
      ["1 hour", "1h"],
      ["2 hours", "2h"],
      ["6 hours", "6h"],
      ["12 hours", "12h"],
      ["1 day", "1d"],
      ["2 days", "2d"]
    ]

    assert_equal expected, result
  end

  test "#schedule_interval should return key for matching cron expression" do
    feed = build(:feed, cron_expression: "0 * * * *")

    assert_equal "1h", feed.schedule_interval
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

  test "#schedule_interval= should set nil for invalid key" do
    feed = build(:feed, cron_expression: "0 * * * *")

    feed.schedule_interval = "invalid"

    assert_nil feed.cron_expression
  end

  test "#schedule_display should return display name for standard interval" do
    feed = build(:feed, cron_expression: "0 * * * *")

    assert_equal "1 hour", feed.schedule_display
  end

  test "#schedule_display should return cron expression for non-standard interval" do
    feed = build(:feed, cron_expression: "15 3 * * *")

    assert_equal "15 3 * * *", feed.schedule_display
  end

  # T018: enabling_requires_recent_preview validation
  def preview_user
    @preview_user ||= create(:user)
  end

  def preview_token_for(feed, generated_at: Time.current)
    PreviewToken.sign(
      user_id: feed.user_id,
      profile_key: feed.feed_profile_key,
      params: feed.params,
      generated_at: generated_at
    )
  end

  def access_token_for(user)
    create(:access_token, :active, user: user)
  end

  test "should require preview_token when creating a feed in enabled state" do
    feed = build(:feed,
      user: preview_user,
      state: :enabled,
      access_token: access_token_for(preview_user),
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" })
    feed.preview_token = nil

    assert_not feed.valid?
    assert feed.errors.of_kind?(:state, :preview_required)
  end

  test "should allow creating a feed in enabled state with a valid preview_token" do
    feed = build(:feed,
      user: preview_user,
      state: :enabled,
      access_token: access_token_for(preview_user),
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" })
    feed.preview_token = preview_token_for(feed)

    assert feed.valid?, feed.errors.full_messages.inspect
  end

  test "should reject creating an enabled feed with a tampered preview_token" do
    feed = build(:feed,
      user: preview_user,
      state: :enabled,
      access_token: access_token_for(preview_user),
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" })
    feed.preview_token = preview_token_for(feed).reverse

    assert_not feed.valid?
    assert feed.errors.of_kind?(:state, :preview_required)
  end

  test "should reject creating an enabled feed when preview_token was signed for different params" do
    feed = build(:feed,
      user: preview_user,
      state: :enabled,
      access_token: access_token_for(preview_user),
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" })
    feed.preview_token = PreviewToken.sign(
      user_id: feed.user_id,
      profile_key: "rss",
      params: { "url" => "https://OTHER.example/feed.xml" },
      generated_at: Time.current
    )

    assert_not feed.valid?
    assert feed.errors.of_kind?(:state, :preview_required)
  end

  test "should reject creating an enabled feed with an expired preview_token" do
    feed = build(:feed,
      user: preview_user,
      state: :enabled,
      access_token: access_token_for(preview_user),
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" })
    feed.preview_token = preview_token_for(feed, generated_at: 2.hours.ago)

    assert_not feed.valid?
    assert feed.errors.of_kind?(:state, :preview_required)
  end

  test "should require preview_token when an enabled feed's params change" do
    feed = create(:feed,
      user: preview_user,
      state: :enabled,
      access_token: access_token_for(preview_user),
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" })
    feed.preview_token = nil
    feed.params = { "url" => "https://other.example/feed.xml" }

    assert_not feed.valid?
    assert feed.errors.of_kind?(:state, :preview_required)
  end

  test "should allow updating an enabled feed's params with a valid preview_token" do
    feed = create(:feed,
      user: preview_user,
      state: :enabled,
      access_token: access_token_for(preview_user),
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" })
    feed.params = { "url" => "https://other.example/feed.xml" }
    feed.preview_token = preview_token_for(feed)

    assert feed.valid?, feed.errors.full_messages.inspect
  end

  test "should not require preview_token when feed remains disabled" do
    feed = create(:feed,
      user: preview_user,
      state: :disabled,
      access_token: access_token_for(preview_user),
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" })
    feed.description = "Updated"

    assert feed.valid?, feed.errors.full_messages.inspect
  end

  test "should not require preview_token for operational-only updates on enabled feed" do
    feed = create(:feed,
      user: preview_user,
      state: :enabled,
      access_token: access_token_for(preview_user),
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" })
    feed.preview_token = nil
    feed.description = "Updated"

    assert feed.valid?, feed.errors.full_messages.inspect
  end

  test "should not require preview_token when toggling state on unchanged enabled feed" do
    # FeedStatusesController#update flow: pure state toggle, no source-side change.
    feed = create(:feed,
      user: preview_user,
      state: :disabled,
      access_token: access_token_for(preview_user),
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" })
    feed.preview_token = nil
    feed.state = :enabled

    assert feed.valid?, feed.errors.full_messages.inspect
  end

  test "should reject an llm_credential belonging to a different user" do
    owner = create(:user)
    stranger = create(:user)
    foreign_credential = create(:llm_credential, user: stranger)

    feed = build(:feed,
                 user: owner,
                 llm_credential: foreign_credential,
                 feed_profile_key: "rss",
                 params: { "url" => "https://example.com/feed.xml" })

    refute feed.valid?
    assert_includes feed.errors[:llm_credential], "must belong to the same user"
  end

  test "should accept its own user's llm_credential" do
    user = create(:user)
    credential = create(:llm_credential, user: user)

    feed = build(:feed,
                 user: user,
                 llm_credential: credential,
                 feed_profile_key: "rss",
                 params: { "url" => "https://example.com/feed.xml" })

    assert feed.valid?, feed.errors.full_messages.inspect
  end

  test "#access_token should reject a token belonging to a different user" do
    owner = create(:user)
    stranger = create(:user)
    foreign_token = create(:access_token, :active, user: stranger)

    feed = build(:feed,
                 user: owner,
                 access_token: foreign_token,
                 feed_profile_key: "rss",
                 params: { "url" => "https://example.com/feed.xml" })

    refute feed.valid?
    assert_includes feed.errors[:access_token], "must belong to the same user"
  end

  test "#access_token should accept the user's own token" do
    user = create(:user)
    token = create(:access_token, :active, user: user)

    feed = build(:feed,
                 user: user,
                 access_token: token,
                 feed_profile_key: "rss",
                 params: { "url" => "https://example.com/feed.xml" })

    assert feed.valid?, feed.errors.full_messages.inspect
  end
end
