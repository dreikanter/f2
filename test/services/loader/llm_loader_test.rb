require "test_helper"

class Loader::LlmLoaderTest < ActiveSupport::TestCase
  test "#loader_instance should keep AI workflows unavailable without inference or usage" do
    feed = build(:feed, feed_profile_key: "llm", params: { "prompt" => "A daily roundup" })

    assert_no_difference -> { LlmUsage.count } do
      error = assert_raises(Loader::Error) { feed.loader_instance.load }
      assert_equal Loader::LlmLoader::UNAVAILABLE_MESSAGE, error.message
    end
    assert_not_requested :any, /./
  end

  test "#load should stage the selected model and return content with native usage" do
    payload = nil
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .with(headers: { "Authorization" => "Bearer loader-test-key" })
      .to_return do |http|
        payload = JSON.parse(http.body)
        { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
      end
    loader = Loader::LlmLoader.new(feed)

    assert_difference "LlmChat.count", 1 do
      assert_no_difference "LlmUsage.count" do
        assert_equal '{"items":[]}', loader.load
      end
    end

    chat = loader.chat.reload
    assert chat.running?
    assert_equal feed.user, chat.user
    assert_equal feed, chat.feed
    assert_equal credential, chat.ai_credential
    assert_equal "llm", chat.profile_key
    assert_equal "scheduled_run", chat.purpose
    assert_equal "openai", chat.requested_provider
    assert_equal "gpt-5-nano", chat.requested_model
    assert_equal %w[system user assistant], chat.messages.map(&:role)
    assert_includes chat.messages.first.content, Loader::LlmPrompts::SAFEGUARDS
    assert_equal "Feed request — what to follow and how to present it:\n\nA daily roundup\n", chat.messages.second.content
    assert_equal "gpt-5-nano", payload.fetch("model")
    assert_equal "web_search", payload.fetch("tools").sole.fetch("type")
    assert_equal true, payload.dig("text", "format", "strict")
    item_schema = payload.dig("text", "format", "schema", "properties", "items", "items")
    assert_equal item_schema.fetch("properties").keys, item_schema.fetch("required")
    assert_not_includes item_schema.fetch("properties"), "uid"
    assert_equal ["body", "source_url"], FeedProfile::UNIVERSAL_OUTPUT_SCHEMA.dig("properties", "items", "items", "required")
    usage = chat.ruby_llm_usages.sole
    assert_equal 40, usage.input_tokens
    assert_equal 20, usage.output_tokens
    assert usage.total_cost.positive?
    assert_equal chat.messages.last, usage.message
    assert_requested request, times: 1
  end

  test "#load should preserve an unlisted model and create a fresh conversation on every call" do
    feed.ai_model = "custom-model"
    prompts = []
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do |http|
      payload = JSON.parse(http.body)
      assert_equal "custom-model", payload.fetch("model")
      prompts << payload.fetch("input")
      { body: completed_response.merge("model" => "custom-model").to_json, headers: { "Content-Type" => "application/json" } }
    end
    loader = Loader::LlmLoader.new(feed)

    assert_difference "LlmChat.count", 2 do
      loader.load
      first_chat = loader.chat
      loader.load
      assert_not_equal first_chat.id, loader.chat.id
    end

    assert_equal prompts.first, prompts.second
    assert_equal "custom-model", loader.chat.model.model_id
    assert_requested request, times: 2
  end

  test "#load should retain preview attribution without saving its temporary feed" do
    temporary_feed = Feed.new(user: feed.user, ai_credential: credential, ai_model: "gpt-5-nano",
                              feed_profile_key: "llm", params: feed.params)
    loader = Loader::LlmLoader.new(temporary_feed, purpose: :preview, usage_feed: feed, deadline_at: 10.seconds.from_now)
    stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: completed_response)

    assert_no_difference "Feed.count" do
      assert_equal '{"items":[]}', loader.load
    end

    assert_equal feed, loader.chat.feed
    assert_equal "preview", loader.chat.purpose
    assert temporary_feed.new_record?
  end

  test "#load should leave invalid JSON for the processor without repairing or settling success" do
    response = completed_response
    response["output"].last["content"].first["text"] = "invalid JSON"
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)
    loader = Loader::LlmLoader.new(feed)

    content = loader.load

    assert_equal "invalid JSON", content
    assert_raises(Processor::LlmProcessor::InvalidOutput) { feed.processor_instance(content).process }
    assert loader.chat.reload.running?
    assert_requested request, times: 1
  end

  test "#load should return strict output that the processor can turn into entries" do
    item = {
      "body" => "A source post", "source_url" => "https://example.com/post",
      "title" => "", "supplementary" => [], "images" => [], "published_at" => ""
    }
    output = { "items" => [item] }
    response = completed_response
    response["output"].last["content"].first["text"] = output.to_json
    stub_request(:post, "https://api.openai.com/v1/responses").to_return do |http|
      schema = JSON.parse(http.body).dig("text", "format", "schema")
      assert JSONSchemer.schema(schema).valid?(output)
      { body: response.to_json, headers: { "Content-Type" => "application/json" } }
    end

    content = Loader::LlmLoader.new(feed).load

    assert_equal item, feed.processor_instance(content).process.entries.sole.raw_data
  end

  ["max_output_tokens", "content_filter"].each do |reason|
    test "#load should reject #{reason} even when the content is valid JSON" do
      response = completed_response.merge("status" => "incomplete", "incomplete_details" => { "reason" => reason })
      request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)
      loader = Loader::LlmLoader.new(feed)

      error = assert_raises(Loader::Error) { loader.load }

      assert_equal "AI response did not complete.", error.message
      assert_equal 1, loader.chat.ruby_llm_usages.count
      assert_requested request, times: 1
    end
  end

  test "#load should reject output at the earlier deadline and retain late native usage" do
    freeze_time do
      loader = Loader::LlmLoader.new(feed, purpose: :preview, deadline_at: 10.seconds.from_now)
      request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do
        travel 10.seconds
        { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
      end

      error = assert_raises(Loader::Error) { loader.load }

      assert_kind_of LlmExecution::DeadlineExceeded, error.cause
      assert loader.chat.reload.interrupted?
      assert_equal "deadline_exceeded", loader.chat.error_category
      assert_equal 1, loader.chat.ruby_llm_usages.count
      assert_requested request, times: 1
    end
  end

  test "#load should translate provider failures without retrying" do
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return_json(status: 429, body: { error: { message: "Rate limited", type: "rate_limit_error" } })
    loader = Loader::LlmLoader.new(feed)

    error = assert_raises(Loader::Error) { loader.load }

    assert_kind_of RubyLLM::Error, error.cause
    assert_equal "failed", loader.chat.ruby_llm_usages.sole.status
    assert_requested request, times: 1
  end

  test "#load should keep external search unavailable without substituting native search" do
    feed.search_credential = create(:search_credential, :active, user: feed.user)

    assert_no_difference "LlmChat.count" do
      assert_raises(Loader::Error) { Loader::LlmLoader.new(feed).load }
    end
    assert_not_requested :any, /./
  end

  test "#load should reject missing or inactive AI settings before creating a chat" do
    feed.ai_model = nil
    assert_no_difference "LlmChat.count" do
      assert_raises(Loader::Error) { Loader::LlmLoader.new(feed).load }
      feed.ai_model = "gpt-5-nano"
      credential.active = false
      assert_raises(Loader::Error) { Loader::LlmLoader.new(feed).load }
      feed.ai_credential = nil
      assert_raises(Loader::Error) { Loader::LlmLoader.new(feed).load }
    end
    assert_not_requested :any, /./
  end

  private

  def credential
    @credential ||= create(:ai_credential, :active, credential_data: { "api_key" => "loader-test-key" })
  end

  def feed
    @feed ||= create(:feed, user: credential.user, ai_credential: credential, ai_model: "gpt-5-nano",
                      feed_profile_key: "llm", params: { "prompt" => "A daily roundup" }, search_credential: nil)
  end

  def completed_response
    JSON.parse(file_fixture("llm_transcripts/completed.json").read)
  end
end
