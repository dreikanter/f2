require "test_helper"

class LlmUsageTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  test "#valid? should return true with the default factory" do
    usage = build(:llm_usage, user: user)
    assert usage.valid?, usage.errors.full_messages.inspect
  end

  test "#valid? should require provider, model, outcome, and timing fields" do
    usage = LlmUsage.new
    refute usage.valid?
    assert usage.errors[:provider].any?
    assert usage.errors[:model].any?
    assert usage.errors[:outcome].any?
    assert usage.errors[:started_at].any?
    assert usage.errors[:finished_at].any?
  end

  test ".stages should expose stage enum values" do
    assert_equal({ "loader" => 0, "processor" => 1, "normalizer" => 2 }, LlmUsage.stages)
  end

  test ".purposes should expose purpose enum values" do
    assert_equal({ "scheduled_run" => 0, "preview" => 1 }, LlmUsage.purposes)
  end

  test ".outcomes should expose outcome enum values" do
    assert_equal(
      { "success" => 0, "schema_error" => 1, "provider_error" => 2, "rate_limited" => 3, "timeout" => 4,
        "pending" => 5, "interrupted" => 6 },
      LlmUsage.outcomes
    )
  end

  test "#valid? should allow feed and ai_credential to be nil for preview / validation calls" do
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

  test "#feed should return the associated feed when provided" do
    feed = create(:feed,
                  user: user,
                  feed_profile_key: "rss",
                  params: { "url" => "http://example.com/feed.xml" })
    usage = create(:llm_usage, user: user, feed: feed)
    assert_equal feed, usage.feed
  end

  test ".start! should commit one pending attempt and reference with independent execution metadata" do
    feed = create(:feed, user: user)
    credential = create(:ai_credential, user: user)
    chat = create(:llm_chat, user: user, feed: feed, ai_credential: credential, purpose: :preview)
    event = create(:event, user: user, subject: feed)

    freeze_time do
      usage = LlmUsage.start!(chat: chat, event: event, retrieval: { "mode" => "native" })

      assert_equal [usage], event.references
      assert usage.pending?
      assert_equal user, usage.user
      assert_equal feed, usage.feed
      assert_equal credential, usage.ai_credential
      assert_equal "preview", usage.purpose
      assert_equal "loader", usage.stage
      assert_equal chat.profile_key, usage.profile_key
      assert_equal chat.requested_provider, usage.provider
      assert_equal chat.requested_model, usage.model
      assert_equal chat.deadline_at, usage.deadline_at
      assert_equal Time.current, usage.started_at
      assert_nil usage.finished_at
      assert_nil usage.duration_ms
      assert_nil usage.input_tokens
      assert_nil usage.output_tokens
      assert_nil usage.cache_read_tokens
      assert_nil usage.cache_write_tokens
      assert_nil usage.thinking_tokens
      assert_nil usage.cost_estimate_cents
      assert_equal({ "mode" => "native" }, usage.retrieval)
    end
  end

  test ".start! should roll back the attempt when its event reference cannot be saved" do
    chat = create(:llm_chat, user: user)
    unsaved_event = build(:event, user: user)

    assert_no_difference ["LlmUsage.count", "EventReference.count"] do
      assert_raises(ActiveRecord::RecordNotSaved) do
        LlmUsage.start!(chat: chat, event: unsaved_event)
      end
    end
  end

  test "#valid? should require a deadline for an unresolved attempt" do
    usage = build(:llm_usage, :pending, deadline_at: nil)

    assert_not usage.valid?
    assert usage.errors[:deadline_at].any?
  end

  test "#settle! should record one observation despite duplicate or stale settlement" do
    usage = create(:llm_usage, :pending, user: user, retrieval: { "mode" => "native" })
    stale = LlmUsage.find(usage.id)

    assert_no_difference "LlmUsage.count" do
      assert usage.settle!(outcome: :success, finished_at: usage.started_at + 1.second,
                          input_tokens: 60, output_tokens: 20, cache_read_tokens: 40,
                          cache_write_tokens: 0, thinking_tokens: 7, cost_estimate_cents: "0.25")
      assert_not stale.settle!(outcome: :provider_error, input_tokens: 0, cost_estimate_cents: 0)
    end

    assert stale.reload.success?
    assert_equal 60, stale.input_tokens
    assert_equal 20, stale.output_tokens
    assert_equal 40, stale.cache_read_tokens
    assert_equal 0, stale.cache_write_tokens
    assert_equal 7, stale.thinking_tokens
    assert_equal BigDecimal("0.25"), stale.cost_estimate_cents
    assert_equal 1000, stale.duration_ms
    assert_equal({ "mode" => "native" }, stale.retrieval)
  end

  test "#settle! should leave missing measurements unknown on a failed request" do
    usage = create(:llm_usage, :pending, user: user)

    assert usage.settle!(outcome: :provider_error, error_message: "Provider unavailable")
    assert usage.provider_error?
    assert usage.finished_at
    assert_nil usage.input_tokens
    assert_nil usage.cache_read_tokens
    assert_nil usage.cost_estimate_cents
    assert_equal "Provider unavailable", usage.error_message
  end

  test "#settle! should resolve a late observation without reopening the extraction" do
    chat = create(:llm_chat, user: user)
    event = create(:event, user: user)
    usage = LlmUsage.start!(chat: chat, event: event)

    travel_to chat.deadline_at + 1.second do
      chat.finish!(status: :interrupted, error_category: "deadline_exceeded")
      usage.interrupt!
      assert_nil usage.finished_at
      assert_nil usage.duration_ms

      assert usage.settle!(outcome: :success, input_tokens: 10, output_tokens: 5)
      assert usage.success?
      assert chat.reload.interrupted?
      assert_equal "deadline_exceeded", chat.error_category
      assert_equal [usage], event.references
      assert_nil usage.cost_estimate_cents
    end
  end

  test "#settle! should reject an unresolved outcome" do
    usage = create(:llm_usage, :pending, user: user)

    assert_raises(ArgumentError) { usage.settle!(outcome: :pending) }
    assert usage.reload.pending?
  end

  test "#interrupt! should not overwrite an observation from another worker" do
    usage = create(:llm_usage, :pending, user: user)
    stale = LlmUsage.find(usage.id)
    usage.settle!(outcome: :success, cost_estimate_cents: "0.25")

    assert_not stale.interrupt!
    assert stale.reload.success?
    assert_equal BigDecimal("0.25"), stale.cost_estimate_cents
  end
end
