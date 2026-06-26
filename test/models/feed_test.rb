require "test_helper"

class FeedTest < ActiveSupport::TestCase
  test "should be valid with all required attributes" do
    feed = build(:feed)
    assert feed.valid?
  end

  test "should require name when enabled" do
    feed = build(:feed, state: :enabled, name: nil)
    assert_not feed.valid?
    assert feed.errors.of_kind?(:name, :blank)
  end

  test "#name should not be required when state is draft" do
    feed = build(:feed, state: :draft, name: nil)
    assert feed.valid?, feed.errors.full_messages.inspect
  end

  test "#name should persist as NULL when state is draft" do
    feed = create(:feed, state: :draft, name: nil)
    assert_nil feed.reload.name
  end

  test "#name should be required when transitioning to enabled" do
    feed = build(:feed, state: :draft, name: nil)
    feed.state = :enabled

    feed.valid?
    assert feed.errors.of_kind?(:name, :blank)
  end

  test "should require unique name when present" do
    user = create(:user)
    create(:feed, user: user, name: "Test Feed")
    feed = build(:feed, user: user, name: "Test Feed")
    assert_not feed.valid?
    assert feed.errors.of_kind?(:name, :taken)
  end

  test "#display_name should return name when present" do
    feed = build(:feed, name: "My Feed")
    assert_equal "My Feed", feed.display_name
  end

  test "#display_name should return placeholder when name is blank" do
    feed = build(:feed, name: nil)
    assert_equal "Untitled feed", feed.display_name
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

  test "should have disabled state when factory builds a feed" do
    feed = build(:feed)
    assert_equal "disabled", feed.state
  end

  test "#state should default to :draft for new records" do
    assert_equal "draft", Feed.new.state
  end

  test "#draft? should return true for draft feeds and false otherwise" do
    assert build(:feed, state: :draft).draft?
    assert_not build(:feed, state: :disabled).draft?
    assert_not build(:feed, state: :enabled).draft?
  end

  test "#disabled? should return true for disabled feeds and false otherwise" do
    assert build(:feed, state: :disabled).disabled?
    assert_not build(:feed, state: :draft).disabled?
    assert_not build(:feed, state: :enabled).disabled?
  end

  test "#enabled? should return true for enabled feeds and false otherwise" do
    assert build(:feed, state: :enabled).enabled?
    assert_not build(:feed, state: :draft).enabled?
    assert_not build(:feed, state: :disabled).enabled?
  end

  test "should support state transitions" do
    feed = create(:feed)

    assert feed.disabled?

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

    freeze_time do
      feed.update!(state: :enabled)

      schedule = feed.reload.feed_schedule
      assert_not_nil schedule
      assert_operator schedule.next_run_at, :>, Time.current, "next_run_at should be in the future so the scheduler does not double-fire"
      assert_not_nil schedule.last_run_at
    end
  end

  test "should not create duplicate feed_schedule when already exists" do
    user = create(:user)
    access_token = create(:access_token, :active, user: user)
    feed = create(:feed, :with_schedule, user: user, state: :disabled, access_token: access_token, target_group: "testgroup")

    existing_schedule = feed.feed_schedule

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

  test ".due should select only enabled feeds (excludes draft and disabled)" do
    freeze_time do
      draft_feed = create(:feed, state: :draft)
      disabled_feed = create(:feed, state: :disabled)
      enabled_feed = create(:feed, state: :enabled)

      due_feeds = Feed.due

      assert_includes due_feeds, enabled_feed
      assert_not_includes due_feeds, draft_feed
      assert_not_includes due_feeds, disabled_feed
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

  test "#can_be_enabled? returns false when feed has a blank name" do
    user = create(:user)
    access_token = create(:access_token, :active, user: user)
    feed = create(:feed, user: user, access_token: access_token, target_group: "test_group", name: "")

    assert_not feed.can_be_enabled?
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

  test "#can_be_previewed? should be true for a non-AI profile with a source" do
    feed = build(:feed, feed_profile_key: "rss", params: { "url" => "https://example.com/feed.xml" })

    assert feed.can_be_previewed?
  end

  test "#can_be_previewed? should be true for an AI profile with an active credential and a model" do
    credential = create(:ai_credential, :active)
    feed = build(:feed, user: credential.user, feed_profile_key: "llm_web_search",
                        params: { "query" => "ruby news" }, ai_credential: credential, ai_model: "claude-sonnet-4-6")

    assert feed.can_be_previewed?
  end

  test "#can_be_previewed? should be false for an AI profile without a model" do
    credential = create(:ai_credential, :active)
    feed = build(:feed, user: credential.user, feed_profile_key: "llm_web_search",
                        params: { "query" => "ruby news" }, ai_credential: credential, ai_model: nil)

    assert_not feed.can_be_previewed?
  end

  test "#can_be_previewed? should be false for an AI profile without a credential" do
    feed = build(:feed, feed_profile_key: "llm_web_search",
                        params: { "query" => "ruby news" }, ai_credential: nil, ai_model: "claude-sonnet-4-6")

    assert_not feed.can_be_previewed?
  end

  test "#can_be_previewed? should be false when the source input is blank" do
    feed = build(:feed, feed_profile_key: "llm_web_search", params: { "query" => "" })

    assert_not feed.can_be_previewed?
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

  test "DEFAULT_SCHEDULE_INTERVAL should be a known schedule interval key" do
    assert_includes Feed::SCHEDULE_INTERVALS.keys, Feed::DEFAULT_SCHEDULE_INTERVAL
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

  # Preview is optional and does not gate enabling.
  def preview_user
    @preview_user ||= create(:user)
  end

  def access_token_for(user)
    create(:access_token, :active, user: user)
  end

  test "#enable should promote a feed to enabled without any preview" do
    feed = create(:feed, :disabled,
      user: preview_user,
      access_token: access_token_for(preview_user),
      target_group: "tg",
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" })

    assert feed.enable, feed.errors.full_messages.inspect
    assert_predicate feed.reload, :enabled?
  end

  test "#enable should fail when a required enabled-state field is missing" do
    feed = create(:feed, :disabled,
      user: preview_user,
      access_token: access_token_for(preview_user),
      target_group: "",
      feed_profile_key: "rss",
      params: { "url" => "https://example.com/feed.xml" })

    assert_not feed.enable
    assert feed.errors.of_kind?(:target_group, :blank)
    assert_predicate feed.reload, :disabled?
  end

  test "should reject an ai_credential belonging to a different user" do
    owner = create(:user)
    stranger = create(:user)
    foreign_credential = create(:ai_credential, user: stranger)

    feed = build(:feed,
                 user: owner,
                 ai_credential: foreign_credential,
                 feed_profile_key: "rss",
                 params: { "url" => "https://example.com/feed.xml" })

    refute feed.valid?
    assert_includes feed.errors[:ai_credential], "must belong to the same user"
  end

  test "should accept its own user's ai_credential" do
    user = create(:user)
    credential = create(:ai_credential, user: user)

    feed = build(:feed,
                 user: user,
                 ai_credential: credential,
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

  test "#enabling an AI feed should require an ai_credential" do
    user = create(:user)
    feed = build(:feed,
                 user: user,
                 access_token: access_token_for(user),
                 feed_profile_key: "llm_website_extractor",
                 params: { "url" => "https://example.com" },
                 ai_credential: nil)
    feed.state = :enabled

    assert_not feed.valid?
    assert_includes feed.errors[:ai_credential], "must be selected for AI-backed feeds"
  end

  test "#enabling an AI feed should reject an inactive ai_credential" do
    user = create(:user)
    credential = create(:ai_credential, :inactive, user: user)
    feed = build(:feed,
                 user: user,
                 access_token: access_token_for(user),
                 feed_profile_key: "llm_website_extractor",
                 params: { "url" => "https://example.com" },
                 ai_credential: credential)
    feed.state = :enabled

    assert_not feed.valid?
    assert_includes feed.errors[:ai_credential], "must be active (currently inactive)"
  end

  test "#enabling an AI feed should accept an active ai_credential" do
    user = create(:user)
    credential = create(:ai_credential, :active, user: user)
    feed = build(:feed,
                 user: user,
                 access_token: access_token_for(user),
                 feed_profile_key: "llm_website_extractor",
                 params: { "url" => "https://example.com" },
                 ai_credential: credential)
    feed.state = :enabled

    assert feed.valid?, feed.errors.full_messages.inspect
  end

  test "#enabling a non-AI feed should not require an ai_credential" do
    user = create(:user)
    feed = build(:feed,
                 user: user,
                 access_token: access_token_for(user),
                 feed_profile_key: "rss",
                 params: { "url" => "https://example.com/feed.xml" },
                 ai_credential: nil)
    feed.state = :enabled

    assert feed.valid?, feed.errors.full_messages.inspect
  end

  test "#enable should promote a valid draft to enabled state" do
    user = create(:user)
    feed = create(:feed,
                  user: user,
                  state: :draft,
                  access_token: access_token_for(user),
                  target_group: "testgroup",
                  cron_expression: "0 * * * *",
                  feed_profile_key: "rss",
                  params: { "url" => "https://example.com/feed.xml" })

    assert feed.enable
    assert_predicate feed, :enabled?
    assert_predicate feed.reload, :enabled?
  end

  test "#enable should return false and roll back in-memory state on validation failure" do
    user = create(:user)
    feed = create(:feed,
                  user: user,
                  state: :draft,
                  access_token: access_token_for(user),
                  target_group: nil,
                  cron_expression: "0 * * * *",
                  feed_profile_key: "rss",
                  params: { "url" => "https://example.com/feed.xml" })

    assert_not feed.enable
    assert_predicate feed, :draft?, "in-memory state should be rolled back to persisted value"
    assert_predicate feed.reload, :draft?
    assert_not_empty feed.errors
  end

  test "#target_group_url should return the group URL when token and group are present" do
    feed = create(:feed, target_group: "testgroup")

    assert_equal "#{feed.access_token.host}/testgroup", feed.target_group_url
  end

  test "#target_group_url should return nil when target_group is blank" do
    feed = create(:feed, target_group: "")

    assert_nil feed.target_group_url
  end

  test "#target_group_url should return nil when access_token is missing" do
    feed = create(:feed, :without_access_token)

    assert_nil feed.target_group_url
  end

  test "#most_recent_repost_at should return latest repost time regardless of original publication date" do
    feed = create(:feed)
    # Older original publication date, but reposted most recently.
    create(:post, :published, feed: feed, published_at: 10.days.ago, reposted_at: 1.hour.ago)
    create(:post, :published, feed: feed, published_at: 1.day.ago, reposted_at: 2.days.ago)
    create(:post, feed: feed, status: :draft, updated_at: Time.current)

    assert_in_delta 1.hour.ago.to_i, feed.most_recent_repost_at.to_i, 1
  end

  test "#most_recent_repost_at should return nil when no published posts" do
    feed = create(:feed)
    create(:post, feed: feed, status: :draft)

    assert_nil feed.most_recent_repost_at
  end

  test "#posts_published_last_week_count should count posts published within the last week" do
    feed = create(:feed)
    create(:post, feed: feed, published_at: 2.days.ago)
    create(:post, feed: feed, published_at: 6.days.ago)
    create(:post, feed: feed, published_at: 10.days.ago)

    assert_equal 2, feed.posts_published_last_week_count
  end

  test "#import_after_enabled should default to false when import_after is blank" do
    feed = build(:feed)

    assert_not feed.import_after_enabled
  end

  test "#import_after_enabled should be true when import_after is set" do
    feed = build(:feed, import_after: Time.utc(2026, 1, 15, 10, 30))

    assert feed.import_after_enabled
    assert_equal "2026-01-15", feed.import_after_date
    assert_equal "10:30", feed.import_after_time
  end

  test "#import_after_enabled= should compose import_after from date and time parts" do
    feed = build(:feed)
    feed.assign_attributes(
      import_after_enabled: "1",
      import_after_date: "2026-01-15",
      import_after_time: "10:30"
    )

    assert feed.valid?, feed.errors.full_messages.inspect
    assert_equal Time.zone.parse("2026-01-15 10:30"), feed.import_after
  end

  test "#import_after_enabled= should default time to midnight when blank" do
    feed = build(:feed)
    feed.assign_attributes(
      import_after_enabled: "1",
      import_after_date: "2026-01-15",
      import_after_time: ""
    )

    assert feed.valid?, feed.errors.full_messages.inspect
    assert_equal Time.zone.parse("2026-01-15 00:00"), feed.import_after
  end

  test "#import_after_enabled= should reset import_after when disabled" do
    feed = build(:feed, import_after: Time.utc(2026, 1, 15, 10, 30))
    feed.assign_attributes(
      import_after_enabled: "0",
      import_after_date: "2026-01-15",
      import_after_time: "10:30"
    )

    assert feed.valid?, feed.errors.full_messages.inspect
    assert_nil feed.import_after
  end

  test "should default to the current time when the date is blank" do
    feed = build(:feed)
    feed.assign_attributes(import_after_enabled: "1", import_after_date: "", import_after_time: "")

    assert feed.valid?, feed.errors.full_messages.inspect
    assert_in_delta Time.current, feed.import_after, 5.seconds
  end

  test "should fall back to the current time for an unparseable date" do
    feed = build(:feed)
    feed.assign_attributes(import_after_enabled: "1", import_after_date: "not-a-date", import_after_time: "10:30")

    assert feed.valid?, feed.errors.full_messages.inspect
    assert_in_delta Time.current, feed.import_after, 5.seconds
  end

  test "#import_after_date should return the submitted value" do
    feed = build(:feed)
    feed.assign_attributes(import_after_enabled: "1", import_after_date: "not-a-date")

    assert_equal "not-a-date", feed.import_after_date
  end

  test "should stay valid when import_after is set directly without parts" do
    feed = build(:feed, import_after: Time.utc(2026, 1, 15))

    assert feed.valid?, feed.errors.full_messages.inspect
  end

  test "#record_refresh_failure! should bump the streak without disabling below the threshold" do
    feed = create(:feed, :enabled, consecutive_failures: 2)

    assert_not feed.record_refresh_failure!
    assert_equal 3, feed.reload.consecutive_failures
    assert feed.enabled?
  end

  test "#record_refresh_failure! should disable the feed and record the count at the threshold" do
    feed = create(:feed, :enabled, consecutive_failures: Feed::MAX_CONSECUTIVE_FAILURES - 1)

    assert feed.record_refresh_failure!

    feed.reload
    assert feed.disabled?
    assert_equal 0, feed.consecutive_failures

    event = Event.find_by(subject: feed, type: "feed_auto_disabled")
    assert_not_nil event
    assert_equal "warning", event.level
    assert_equal Feed::MAX_CONSECUTIVE_FAILURES, event.metadata["error_count"]
    assert_nil Event.find_by(subject: feed, type: "feed_disabled")
  end

  test "#record_refresh_failure! should not disable a feed already disabled elsewhere" do
    feed = create(:feed, :enabled, consecutive_failures: Feed::MAX_CONSECUTIVE_FAILURES - 1)
    Feed.where(id: feed.id).update_all(state: Feed.states[:disabled])

    assert_not feed.record_refresh_failure!
    assert_nil Event.find_by(subject: feed, type: "feed_auto_disabled")
  end

  test "#disable_due_to_unavailable_target! should disable the feed and record a deterministic reason" do
    feed = create(:feed, :enabled, target_group: "cats", consecutive_failures: 3)

    feed.disable_due_to_unavailable_target!(reason: :posting_denied, details: "raw err")

    feed.reload
    assert feed.disabled?
    assert_equal 0, feed.consecutive_failures

    event = Event.find_by(subject: feed, type: "feed_target_group_unavailable")
    assert_not_nil event
    assert_equal "warning", event.level
    assert_equal "posting_denied", event.metadata["reason"]
    assert_equal "cats", event.metadata["target_group"]
    assert_equal "raw err", event.metadata["details"]
    assert_equal "", event.message
  end

  test "#disable_due_to_unavailable_target! should omit reason and details from metadata when not given" do
    feed = create(:feed, :enabled, target_group: "cats")

    feed.disable_due_to_unavailable_target!

    event = Event.find_by(subject: feed, type: "feed_target_group_unavailable")
    assert_equal "cats", event.metadata["target_group"]
    assert_not event.metadata.key?("details")
    assert_not event.metadata.key?("reason")
  end

  test "#reset_refresh_failures! should clear the streak" do
    feed = create(:feed, :enabled, consecutive_failures: 4)

    feed.reset_refresh_failures!

    assert_equal 0, feed.reload.consecutive_failures
  end

  test "#reset_schedule! should create a schedule with next_run_at = now when none exists" do
    feed = create(:feed, :enabled, cron_expression: "0 * * * *")
    feed.feed_schedule&.destroy
    feed.reload

    freeze_time do
      schedule = feed.reset_schedule!

      assert_not_nil schedule
      assert_equal Time.current, schedule.next_run_at
      assert_equal Time.current, schedule.last_run_at
    end
  end

  test "#reset_schedule! should update next_run_at to now when schedule already exists" do
    feed = create(:feed, :enabled, cron_expression: "0 * * * *")
    existing_schedule = feed.feed_schedule || create(:feed_schedule, feed: feed, next_run_at: 1.hour.from_now)

    freeze_time do
      returned = feed.reset_schedule!

      assert_equal existing_schedule.id, returned.id
      assert_equal Time.current, returned.reload.next_run_at
    end
  end

  test "#defer_schedule! should create a schedule with next_run_at in the future when none exists" do
    feed = create(:feed, :enabled, cron_expression: "0 * * * *")
    feed.feed_schedule&.destroy
    feed.reload

    freeze_time do
      schedule = feed.defer_schedule!

      assert_not_nil schedule
      assert_operator schedule.next_run_at, :>, Time.current
      assert_not_nil schedule.last_run_at
    end
  end

  test "#defer_schedule! should update next_run_at to the future when schedule already exists" do
    feed = create(:feed, :enabled, cron_expression: "0 * * * *")
    existing_schedule = feed.feed_schedule || create(:feed_schedule, feed: feed, next_run_at: Time.current)

    freeze_time do
      returned = feed.defer_schedule!

      assert_equal existing_schedule.id, returned.id
      assert_operator returned.reload.next_run_at, :>, Time.current
    end
  end
end
