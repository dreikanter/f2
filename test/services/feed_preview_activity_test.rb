require "test_helper"

class FeedPreviewActivityTest < ActiveSupport::TestCase
  ENDPOINT = "https://api.openai.com/v1/responses"

  def credential
    @credential ||= create(:ai_credential, :active, provider: "openai",
                            available_models: [{ "id" => "new-model" }])
  end

  def preview
    @preview ||= create(:feed_preview, user: credential.user, ai_credential: credential, ai_model: "new-model",
                         feed_profile_key: "llm", params: { "prompt" => "Find one recent release announcement" })
  end

  def response(text, search: false)
    output = [{ type: "message", role: "assistant", content: [{ type: "output_text", text: text }] }]
    output.unshift(type: "web_search_call", status: "completed") if search
    { status: 200, headers: { "Content-Type" => "application/json" }, body: {
      status: "completed", output: output, usage: { input_tokens: 40, output_tokens: 20 }
    }.to_json }
  end

  def stub_native
    stub_request(:post, ENDPOINT).to_return(
      response("Release announcement: https://example.com/release", search: true),
      response({ items: [{ body: "Release announcement", source_url: "https://example.com/release" }] }.to_json)
    )
  end

  def execute
    FeedPreviewWorkflow.new(preview, run_id: preview.run_id).execute
  end

  def activity
    Event.where(type: "feed_preview", user: credential.user).sole
  end

  test "#execute should expose preview usage through one completed activity event without publishing" do
    unrelated = create(:llm_usage, user: credential.user, purpose: :preview)
    stub_native

    assert_no_difference -> { Post.count } do
      execute
    end

    assert preview.reload.ready?
    assert_includes preview.posts_data.sole["content"], "https://example.com/release"
    assert_equal "completed", activity.metadata["status"]
    assert_equal "info", activity.level
    assert_equal credential, activity.subject
    assert_equal 2, activity.metadata.dig("stats", "llm_calls")
    assert_nil activity.metadata.dig("stats", "llm_cost_cents")
    usages = activity.references.grep(LlmUsage)
    assert_equal 2, usages.size
    assert usages.all?(&:preview?)
    assert usages.all? { |usage| usage.feed_id.nil? }
    assert_equal 80, usages.sum(&:input_tokens)
    assert_equal 1, usages.sum { |usage| usage.retrieval["search_calls"].to_i }
    assert_not_includes usages.map(&:id), unrelated.id
    assert_not_includes activity.metadata.to_json, preview.params["prompt"]
    assert_not_includes activity.metadata.to_json, "Release announcement"
  end

  test "#execute should reference failed attempts and keep their unknown cost visible" do
    stub_request(:post, ENDPOINT).to_return(status: 401, headers: { "Content-Type" => "application/json" },
                                           body: { error: { message: "Invalid key" } }.to_json)

    assert_raises(LlmClient::AuthError) { execute }

    assert preview.reload.failed?
    assert_equal "failed", activity.metadata["status"]
    assert_equal "warning", activity.level
    assert_equal "provider_error", activity.references.sole.outcome
    assert_equal 1, activity.metadata.dig("stats", "llm_calls")
    assert_nil activity.metadata.dig("stats", "llm_cost_cents")
  end

  test "#execute should retain paid usage for a superseded preview without overwriting its replacement" do
    original_run = preview.run_id
    replacement_run = SecureRandom.uuid
    replies = [response("Original joke"), response('{"items":[]}')]
    stub_request(:post, ENDPOINT).to_return do
      preview.update!(run_id: replacement_run, status: :pending)
      replies.shift
    end

    FeedPreviewWorkflow.new(preview, run_id: original_run).execute

    assert preview.reload.pending?
    assert_equal replacement_run, preview.run_id
    assert_nil preview.data
    assert_equal "interrupted", activity.metadata["status"]
    assert_equal 2, activity.references.grep(LlmUsage).size
  end

  test "#execute should not create activity or usage again for an already completed run" do
    stub_native
    execute

    assert_no_difference [-> { Event.count }, -> { LlmUsage.count }] do
      execute
    end

    assert_equal "completed", activity.metadata["status"]
    assert_requested :post, ENDPOINT, times: 2
  end

  test "#execute should replace the started event with a fresh terminal event for polling" do
    started_id = nil
    stub_request(:post, ENDPOINT).to_return do
      started_id = activity.id
      assert_equal "started", activity.metadata["status"]
      response("")
    end

    execute

    assert_not_equal started_id, activity.id
    assert_not Event.exists?(started_id)
    assert_equal "completed", activity.metadata["status"]
    assert_equal 1, activity.references.grep(LlmUsage).size
  end

  test "#finish! should retain external search references and known zero cost" do
    record = FeedPreviewActivity.new(preview)
    search = create(:search_credential, :active, user: credential.user)
    search_event = WebSearchUsage.record!(credential: search, refresh_event: record.event)
    usage = create(:llm_usage, user: credential.user, purpose: :preview, cost_estimate_cents: 0)
    record.event.event_references.create!(reference: usage)

    record.finish!(status: "completed", stats: { normalized_posts: 1 })

    assert_equal [search_event.id], WebSearchUsage.referenced_by(record.event).pluck(:id)
    assert_equal 1, record.event.metadata.dig("stats", "search_calls")
    assert_equal 0, record.event.metadata.dig("stats", "llm_cost_cents")
    assert_equal 1, record.event.metadata.dig("stats", "normalized_posts")
  end
end
