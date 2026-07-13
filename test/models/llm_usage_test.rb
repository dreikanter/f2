require "test_helper"

class LlmUsageTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  test "should be valid with the default factory" do
    usage = build(:llm_usage, user: user)
    assert usage.valid?, usage.errors.full_messages.inspect
  end

  test "should require provider, model, outcome, and timing fields" do
    usage = LlmUsage.new
    refute usage.valid?
    assert usage.errors[:provider].any?
    assert usage.errors[:model].any?
    assert usage.errors[:outcome].any?
    assert usage.errors[:started_at].any?
    assert usage.errors[:finished_at].any?
  end

  test "should expose stage enum values" do
    assert_equal({ "loader" => 0, "processor" => 1, "normalizer" => 2 }, LlmUsage.stages)
  end

  test "should expose purpose enum values" do
    assert_equal({ "scheduled_run" => 0, "preview" => 1 }, LlmUsage.purposes)
  end

  test "should expose outcome enum values" do
    assert_equal(
      { "success" => 0, "schema_error" => 1, "provider_error" => 2, "rate_limited" => 3, "timeout" => 4 },
      LlmUsage.outcomes
    )
  end

  test "should allow feed and ai_credential to be nil for preview / validation calls" do
    usage = build(:llm_usage, user: user, feed: nil, ai_credential: nil, purpose: :preview)
    assert usage.valid?
  end

  test ".within_stats_period should include only usages created within the period" do
    recent = create(:llm_usage, user: user)
    stale = create(:llm_usage, user: user, created_at: LlmUsage::STATS_PERIOD.ago - 1.day)

    result = LlmUsage.within_stats_period

    assert_includes result, recent
    assert_not_includes result, stale
  end

  test "should belong to a feed when provided" do
    feed = create(:feed,
                  user: user,
                  feed_profile_key: "rss",
                  params: { "url" => "http://example.com/feed.xml" })
    usage = create(:llm_usage, user: user, feed: feed)
    assert_equal feed, usage.feed
  end
end
