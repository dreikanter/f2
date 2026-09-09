require "test_helper"

class LlmClient::ErrorMiddlewareTest < ActiveSupport::TestCase
  ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"
  MALFORMED_ERROR = { error: "No endpoints found that support tool use." }.freeze

  def credential
    @credential ||= create(:ai_credential, :active, provider: "openrouter", available_models: [
      { "id" => "example/future-model", "metadata" => { "pricing" => { "input" => 1, "output" => 2 } } }
    ])
  end

  def search_credential
    @search_credential ||= create(:search_credential, :active, user: credential.user)
  end

  def context
    @context ||= LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader,
                                           model: "example/future-model", search_credential: search_credential)
  end

  def call
    LlmClient.new(credential).call(context, prompt: "Find a recent release", output_schema: nil, web: true)
  end

  def json(body, status: 200)
    { status: status, headers: { "Content-Type" => "application/json" }, body: body.to_json }
  end

  def tool_round(id = "fetch-1")
    json({ choices: [{ message: { role: "assistant", content: nil, tool_calls: [
      { id: id, type: "function", function: { name: LlmClient::Tools::WebFetch.new.name,
                                             arguments: { url: "ftp://example.com" }.to_json } }
    ] }, finish_reason: "tool_calls" }], usage: { prompt_tokens: 100, completion_tokens: 30,
      prompt_tokens_details: { cached_tokens: 20, cache_write_tokens: 10 } } })
  end

  test "#call should account for a malformed router rejection without a capability fallback" do
    request = stub_request(:post, ENDPOINT).to_return(json(MALFORMED_ERROR, status: 404))
    reported = []

    error = Rails.error.stub(:report, ->(exception, **) { reported << exception }) do
      assert_raises(LlmClient::ProviderError) { call }
    end

    assert_instance_of LlmClient::ProviderError, error
    assert_equal "AI provider returned a malformed error response (HTTP 404)", error.message
    malformed = error.cause
    assert_instance_of LlmClient::ErrorMiddleware::MalformedResponse, malformed
    assert_instance_of TypeError, malformed.cause
    assert_equal 404, malformed.response.status
    assert_equal MALFORMED_ERROR.stringify_keys, JSON.parse(malformed.response.body)
    assert_equal [malformed], reported
    usage = LlmUsage.sole
    assert_equal "provider_error", usage.outcome
    assert_equal error.message, usage.error_message
    assert_equal 0, usage.input_tokens
    assert_equal 0, usage.output_tokens
    assert_nil usage.cost_estimate_cents
    assert_same false, usage.retrieval["token_usage_reported"]
    assert_equal "external", usage.retrieval["mode"]
    assert_not context.tools_disabled
    assert_not context.native_search_disabled
    assert credential.reload.active?
    assert_requested request, times: 1
  end

  test "#call should retain tokens from every completed tool round before a malformed rejection" do
    request = stub_request(:post, ENDPOINT).to_return(tool_round, tool_round("fetch-2"),
                                                     json(MALFORMED_ERROR, status: 404))

    assert_raises(LlmClient::ProviderError) { call }

    usage = LlmUsage.sole
    assert_equal "provider_error", usage.outcome
    assert_equal 140, usage.input_tokens
    assert_equal 60, usage.output_tokens
    assert_equal 40, usage.cache_read_tokens
    assert_equal 20, usage.cache_write_tokens
    assert_nil usage.cost_estimate_cents
    assert_same false, usage.retrieval["token_usage_reported"]
    assert_equal 2, context.tool_budget.spent
    assert_not context.tools_disabled
    assert_requested request, times: 3
  end

  test "#call should normalize malformed nested error details and error lists without retrying" do
    [
      { error: 42 },
      { error: { message: "Unsupported tools", metadata: "invalid" } },
      { error: { message: "Unsupported tools", metadata: { raw: MALFORMED_ERROR.to_json } } },
      [nil]
    ].each do |body|
      @context = nil
      stub_request(:post, ENDPOINT).to_return(json(body, status: 400))

      assert_difference -> { LlmUsage.count }, 1 do
        error = assert_raises(LlmClient::ProviderError) { call }
        assert_instance_of LlmClient::ErrorMiddleware::MalformedResponse, error.cause
      end

      assert_nil LlmUsage.order(:created_at).last.cost_estimate_cents
      assert_not context.tools_disabled
    end

    assert_requested :post, ENDPOINT, times: 4
  end

  test "#call should handle malformed errors on the hosted search transport without retrying" do
    @context = LlmClient::CallContext.new(feed: nil, profile_key: "llm", stage: :loader, model: "example/future-model")
    request = stub_request(:post, ENDPOINT).to_return(json(MALFORMED_ERROR, status: 500))

    assert_raises(LlmClient::ProviderError) { call }

    usage = LlmUsage.sole
    assert_equal "provider_error", usage.outcome
    assert_nil usage.cost_estimate_cents
    assert_equal "provider", usage.retrieval["mode"]
    assert_not context.native_search_disabled
    assert_requested request, times: 1
  end

  test "#execute should fail the preview and link partial usage to its failed activity" do
    feed = create(:feed, :draft, user: credential.user, ai_credential: credential, ai_model: context.model,
                         search_credential: search_credential, feed_profile_key: "llm", params: { "prompt" => "Find news" })
    preview = create(:feed_preview, user: feed.user, feed: feed, ai_credential: credential, ai_model: feed.ai_model,
                                    search_credential: search_credential, feed_profile_key: "llm", params: feed.params)
    request = stub_request(:post, ENDPOINT).to_return(tool_round, json(MALFORMED_ERROR, status: 404))

    assert_no_difference -> { Post.count } do
      assert_raises(LlmClient::ProviderError) do
        FeedPreviewWorkflow.new(preview, run_id: preview.run_id).execute
      end
    end

    assert preview.reload.failed?
    assert_nil preview.ready_at
    assert_empty preview.posts_data
    usage = feed.llm_usages.sole
    assert_equal "preview", usage.purpose
    assert_equal "provider_error", usage.outcome
    assert_equal 70, usage.input_tokens
    assert_equal 30, usage.output_tokens
    assert_equal 20, usage.cache_read_tokens
    assert_equal 10, usage.cache_write_tokens
    assert_nil usage.cost_estimate_cents
    event = feed.events.find_by!(type: "feed_preview")
    assert_equal "failed", event.metadata["status"]
    assert_equal [usage], event.references.grep(LlmUsage)
    assert_equal 1, event.metadata.dig("stats", "llm_calls")
    assert_nil event.metadata.dig("stats", "llm_cost_cents")
    assert_requested request, times: 2
  end

  test "#call should let tool programming errors propagate unchanged" do
    request = stub_request(:post, ENDPOINT).to_return(tool_round)

    [TypeError, NoMethodError, RuntimeError].each do |error_class|
      @context = nil
      original = error_class.new("broken URL validation")

      assert_no_difference -> { LlmUsage.count } do
        PublicUrl.stub(:safe?, ->(*) { raise original }) do
          assert_same original, assert_raises(error_class) { call }
        end
      end
    end

    assert_requested request, times: 3
  end

  test "#call should leave SDK errors outside HTTP error handling distinguishable" do
    request = stub_request(:post, ENDPOINT).to_return(json({ choices: 42 }))

    assert_no_difference -> { LlmUsage.count } do
      assert_raises(TypeError) { call }
    end

    assert_requested request, times: 1
  end
end
