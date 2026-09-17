require "test_helper"

class Loader::LlmLoaderTest < ActiveSupport::TestCase
  test "#load should stage the selected model with bundled metadata when the database is empty" do
    assert_empty RubyLLM::ActiveRecord::Model.all
    RubyLLM.models.load_from_store
    payload = nil
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .with(headers: { "Authorization" => "Bearer loader-test-key" })
      .to_return do |http|
        payload = JSON.parse(http.body)
        { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
      end
    loader = Loader::LlmLoader.new(feed)

    assert_difference "LlmChat.count", 1 do
      result = loader.load
      assert_instance_of LlmResult, result
      assert_equal '{"items":[]}', result.content
    end

    chat = feed.llm_chats.sole
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

  test "#load should use updated model limits and pricing after another worker refreshes the catalog" do
    model = create(:llm_model, model_id: feed.ai_model, max_output_tokens: 8_192,
                              pricing: { text_tokens: { standard: { input_per_million: 1, output_per_million: 2 } } })
    RubyLLM.models.load_from_store
    model.update!(max_output_tokens: 1_024,
                  pricing: { text_tokens: { standard: { input_per_million: 3, output_per_million: 4 } } })
    payload = nil
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .with(headers: { "Authorization" => "Bearer loader-test-key" })
      .to_return do |http|
        payload = JSON.parse(http.body)
        { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
      end

    Loader::LlmLoader.new(feed).load

    assert_equal feed.ai_model, payload.fetch("model")
    assert_equal 1_024, payload.fetch("max_output_tokens")
    usage = feed.llm_chats.sole.ruby_llm_usages.sole
    assert_equal BigDecimal("0.0002"), usage.total_cost
    assert_requested request, times: 1
    assert_not_requested :get, /./
  end

  test "#load should use persisted metadata for a model added after the worker cached its catalog" do
    RubyLLM.models.load_from_json
    model = create(:llm_model, model_id: "newly-listed-model", max_output_tokens: 2_048,
                              pricing: { text_tokens: { standard: { input_per_million: 1, output_per_million: 2 } } })
    feed.ai_model = model.model_id
    payload = nil
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .with(headers: { "Authorization" => "Bearer loader-test-key" })
      .to_return do |http|
        payload = JSON.parse(http.body)
        response = completed_response.merge("model" => model.model_id)
        { body: response.to_json, headers: { "Content-Type" => "application/json" } }
      end

    Loader::LlmLoader.new(feed).load

    assert_equal model.model_id, payload.fetch("model")
    assert_equal 2_048, payload.fetch("max_output_tokens")
    usage = feed.llm_chats.sole.ruby_llm_usages.sole
    assert_equal BigDecimal("0.00008"), usage.total_cost
    assert_requested request, times: 1
    assert_not_requested :get, /./
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
      first_chat = feed.llm_chats.sole
      loader.load
      assert_equal 2, feed.llm_chats.count
      assert feed.llm_chats.where.not(id: first_chat.id).sole.running?
    end

    assert_equal prompts.first, prompts.second
    assert_equal ["custom-model"], feed.llm_chats.map { |chat| chat.model.model_id }.uniq
    assert_requested request, times: 2
  end

  test "#load should retain preview attribution without saving its temporary feed" do
    freeze_time do
      temporary_feed = Feed.new(user: feed.user, ai_credential: credential, ai_model: "gpt-5-nano",
                                feed_profile_key: "llm", params: feed.params)
      loader = temporary_feed.loader_instance(purpose: :preview, usage_feed: feed, deadline_at: 10.seconds.from_now)
      stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: completed_response)

      assert_no_difference "Feed.count" do
        assert_equal '{"items":[]}', loader.load.content
      end

      chat = feed.llm_chats.sole
      assert_equal "preview", chat.purpose
      assert_equal 10.seconds.from_now, chat.deadline_at
      assert temporary_feed.new_record?
    end
  end

  test "#load should leave invalid JSON for the processor without repairing or settling success" do
    response = completed_response
    response["output"].last["content"].first["text"] = "invalid JSON"
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)
    loader = Loader::LlmLoader.new(feed)

    result = loader.load

    assert_equal "invalid JSON", result.content
    assert feed.llm_chats.sole.running?
    assert_requested request, times: 1
  end

  test "#load should send a strict ten-item limit that the processor also enforces" do
    item = {
      "body" => "A source post", "source_url" => "https://example.com/post",
      "title" => "", "supplementary" => [], "images" => [], "published_at" => ""
    }
    items = Array.new(10) { |index| item.merge("source_url" => "https://example.com/post/#{index}") }
    output = { "items" => items }
    response = completed_response
    response["output"].last["content"].first["text"] = output.to_json
    stub_request(:post, "https://api.openai.com/v1/responses").to_return do |http|
      schema = JSON.parse(http.body).dig("text", "format", "schema")
      assert JSONSchemer.schema(schema).valid?(output)
      assert_not JSONSchemer.schema(schema).valid?({ "items" => items + [item] })
      { body: response.to_json, headers: { "Content-Type" => "application/json" } }
    end

    content = Loader::LlmLoader.new(feed).load

    assert_equal items, feed.processor_instance(content).process.entries.map(&:raw_data)
  end

  ["max_output_tokens", "content_filter"].each do |reason|
    test "#load should reject #{reason} even when the content is valid JSON" do
      response = completed_response.merge("status" => "incomplete", "incomplete_details" => { "reason" => reason })
      request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)
      loader = Loader::LlmLoader.new(feed)

      error = assert_raises(Loader::Error) { loader.load }

      assert_equal "AI response did not complete.", error.message
      chat = feed.llm_chats.sole
      assert chat.failed?
      assert_equal "Loader::Error", chat.error_category
      assert_equal 1, chat.ruby_llm_usages.count
      assert_requested request, times: 1
    end
  end

  test "#load should reject output at the earlier deadline and retain late RubyLLM usage" do
    freeze_time do
      loader = Loader::LlmLoader.new(feed, purpose: :preview, deadline_at: 10.seconds.from_now)
      request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do
        travel 10.seconds
        { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
      end

      error = assert_raises(Loader::Error) { loader.load }

      assert_kind_of LlmExecution::DeadlineExceeded, error.cause
      chat = feed.llm_chats.sole
      assert chat.interrupted?
      assert_equal "deadline_exceeded", chat.error_category
      assert_equal 1, chat.ruby_llm_usages.count
      assert_requested request, times: 1
    end
  end

  test "#load should translate provider failures without retrying" do
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return_json(status: 429, body: { error: { message: "Rate limited", type: "rate_limit_error" } })
    loader = Loader::LlmLoader.new(feed)

    error = assert_raises(Loader::Error) { loader.load }

    assert_equal "AI request failed. Please try again later.", error.message
    assert_kind_of RubyLLM::Error, error.cause
    chat = feed.llm_chats.sole
    assert chat.failed?
    assert_equal error.cause.class.name, chat.error_category
    assert_equal "failed", chat.ruby_llm_usages.sole.status
    assert_requested request, times: 1
  end

  test "#load should fail the chat when native search exceeds its execution budget" do
    response = completed_response
    response["output"] = Array.new(5) do |index|
      { "type" => "web_search_call", "id" => "search_#{index}", "status" => "completed" }
    end + response["output"].select { |item| item["type"] == "message" }
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)

    error = assert_raises(Loader::Error) { Loader::LlmLoader.new(feed).load }

    assert_equal "AI request exceeded its execution limits.", error.message
    assert_kind_of LlmExecution::ToolLimitExceeded, error.cause
    chat = feed.llm_chats.sole
    assert chat.failed?
    assert_equal "LlmExecution::ToolLimitExceeded", chat.error_category
    assert_equal 1, chat.ruby_llm_usages.count
    assert_requested request, times: 1
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

  test "#load should reject external search before creating a chat or making requests" do
    feed.search_credential = create(:search_credential, :active, user: feed.user)

    assert_no_difference "LlmChat.count" do
      error = assert_raises(Loader::Error) { Loader::LlmLoader.new(feed).load }

      assert_equal "External search is not supported yet.", error.message
    end
    assert_not_requested :any, /./
  end

  test "#load should reject external search even when its settings are exposed" do
    feed.search_credential = create(:search_credential, :active, user: feed.user)

    Rails.configuration.x.stub(:external_search_enabled, true) do
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
