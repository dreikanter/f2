require "test_helper"

class FeedPreviewActivityTest < ActiveSupport::TestCase
  def credential
    @credential ||= create(:ai_credential, :active, provider: "openai")
  end

  def preview
    @preview ||= create(:feed_preview, user: credential.user, ai_credential: credential,
                         feed_profile_key: "llm", params: { "prompt" => "A daily roundup" })
  end

  def saved_feed
    @saved_feed ||= create(:feed, :draft, user: credential.user, ai_credential: credential,
                           feed_profile_key: "llm", params: { "prompt" => "Saved prompt" })
  end

  test "#finish! should transfer only its own usage to a new completed event" do
    unrelated = create(:llm_usage, user: credential.user, purpose: :preview)
    record = FeedPreviewActivity.new(preview)
    started_id = record.event.id
    usage = create(:llm_usage, user: credential.user, purpose: :preview, cost_estimate_cents: nil)
    record.event.event_references.create!(reference: usage)

    assert_no_difference -> { Post.count } do
      record.finish!(status: "completed", stats: { normalized_posts: 1 })
    end

    assert_not Event.exists?(started_id)
    assert_not_equal started_id, record.event.id
    assert_equal "completed", record.event.metadata["status"]
    assert_equal "info", record.event.level
    assert_empty record.event.message
    assert_not record.event.metadata.key?("error")
    assert_equal credential, record.event.subject
    assert_equal [usage], record.event.references
    assert_not_includes record.event.references, unrelated
    assert_equal 1, record.event.metadata.dig("stats", "llm_calls")
    assert_nil record.event.metadata.dig("stats", "llm_cost_cents")
    assert_not_includes record.event.metadata.to_json, preview.params["prompt"]
  end

  test "#finish! should preserve failed usage and attribute saved feed previews without editing the feed" do
    preview.update!(feed: saved_feed)
    original = saved_feed.attributes
    record = FeedPreviewActivity.new(preview)
    usage = create(:llm_usage, user: credential.user, feed: saved_feed, purpose: :preview,
                              outcome: :provider_error, cost_estimate_cents: nil)
    record.event.event_references.create!(reference: usage)

    error = Loader::Error.new("Provider request timed out")
    record.finish!(status: "failed", stats: { failed_at_step: :load_feed_contents }, error: error)
    record.event.reload

    assert_equal error.message, record.event.message
    assert_equal "Loader::Error", record.event.metadata.dig("error", "class")
    assert_equal error.message, record.event.metadata.dig("error", "message")
    assert_equal "load_feed_contents", record.event.metadata.dig("error", "stage")
    assert_equal "failed", record.event.metadata["status"]
    assert_equal "warning", record.event.level
    assert_equal saved_feed, record.event.subject
    assert_equal [usage], record.event.references
    assert_nil record.event.metadata.dig("stats", "llm_cost_cents")
    assert_equal original, saved_feed.reload.attributes
  end

  test "#finish! should preserve usage for an interrupted preview" do
    record = FeedPreviewActivity.new(preview)
    usage = create(:llm_usage, user: credential.user, purpose: :preview)
    record.event.event_references.create!(reference: usage)

    error = Loader::Error.new("Provider request timed out")
    record.finish!(status: "interrupted", stats: { failed_at_step: :load_feed_contents }, error: error)

    assert_equal "interrupted", record.event.metadata["status"]
    assert_equal error.message, record.event.metadata.dig("error", "message")
    assert_equal "warning", record.event.level
    assert_equal [usage], record.event.references
  end

  test "#finish! should not replace a terminal event twice" do
    record = FeedPreviewActivity.new(preview)
    record.finish!(status: "completed", stats: {})
    terminal_id = record.event.id

    assert_no_difference -> { Event.count } do
      record.finish!(status: "failed", stats: {})
    end

    assert_equal terminal_id, record.event.id
    assert_equal "completed", record.event.metadata["status"]
  end

  test "#finish! should retain external search references and known zero cost" do
    preview.update!(feed: saved_feed)
    record = FeedPreviewActivity.new(preview)
    search = create(:search_credential, :active, user: credential.user)
    search_event = WebSearchUsage.record!(credential: search, refresh_event: record.event)
    usage = create(:llm_usage, user: credential.user, purpose: :preview, cost_estimate_cents: 0)
    record.event.event_references.create!(reference: usage)

    record.finish!(status: "completed", stats: { normalized_posts: 1 })

    assert_equal [search_event.id], WebSearchUsage.referenced_by(record.event).pluck(:id)
    assert_equal [search_event.id], WebSearchUsage.for_feed(saved_feed).pluck(:id)
    assert_equal 1, record.event.metadata.dig("stats", "search_calls")
    assert_equal 0, record.event.metadata.dig("stats", "llm_cost_cents")
    assert_equal 1, record.event.metadata.dig("stats", "normalized_posts")
  end

  test "#finish! should sum fractional costs before serializing the event total as a JSON number" do
    record = FeedPreviewActivity.new(preview)
    2.times do
      usage = create(:llm_usage, user: credential.user, purpose: :preview, cost_estimate_cents: "0.4")
      record.event.event_references.create!(reference: usage)
    end

    record.finish!(status: "completed", stats: {})

    stats = record.event.reload.metadata.fetch("stats")
    assert_equal 2, stats["llm_calls"]
    assert_equal 0.8, stats["llm_cost_cents"]
  end
end
