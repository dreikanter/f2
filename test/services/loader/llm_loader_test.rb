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
    assert_includes chat.messages.first.content, Loader::LlmPrompts::TASK
    assert_includes chat.messages.first.content, Loader::LlmPrompts::OUTPUT_CONTRACT
    assert_includes chat.messages.first.content, Loader::LlmPrompts::SAFEGUARDS
    assert_not_includes chat.messages.first.content, feed.source_input
    assert_equal "Feed request — what to follow and how to present it:\n\nA daily roundup\n", chat.messages.second.content
    assert_equal chat.messages.first.content, payload.fetch("instructions")
    assert_equal ["Return at most 3 items."], payload.fetch("instructions").scan(/Return at most \d+ items\./)
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

  test "#load should isolate each feed's response limit in the schema and instructions" do
    limited_feed = create(:feed, user: feed.user, feed_profile_key: "llm", ai_credential: credential,
                                ai_model: feed.ai_model, params: { "prompt" => "Write stories", "max_items" => 1 })
    payloads = []
    stub_request(:post, "https://api.openai.com/v1/responses").to_return do |http|
      payloads << JSON.parse(http.body)
      { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
    end

    Loader::LlmLoader.new(limited_feed).load
    Loader::LlmLoader.new(feed).load

    assert_equal 1, payloads.first.dig("text", "format", "schema", "properties", "items", "maxItems")
    assert_equal 3, payloads.last.dig("text", "format", "schema", "properties", "items", "maxItems")
    assert_equal ["Return at most 1 item."], payloads.first.fetch("instructions").scan(/Return at most \d+ items?\./)
    assert_equal ["Return at most 3 items."], payloads.last.fetch("instructions").scan(/Return at most \d+ items?\./)
    assert_equal 10, FeedProfile::UNIVERSAL_OUTPUT_SCHEMA.dig("properties", "items", "maxItems")
  end

  test "#load should use the default limit when a stored value is invalid" do
    feed.update_column(:params, feed.params.merge("max_items" => "abc"))
    payload = nil
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do |http|
      payload = JSON.parse(http.body)
      {
        body: completed_response(content: { "items" => [original_item] }.to_json).to_json,
        headers: { "Content-Type" => "application/json" }
      }
    end

    content = Loader::LlmLoader.new(feed.reload).load
    entries = feed.processor_instance(content).process.entries

    assert_equal original_item, entries.sole.raw_data
    assert_equal LlmOutput::DEFAULT_MAX_ITEMS, payload.dig("text", "format", "schema", "properties", "items", "maxItems")
    assert_includes feed.llm_chats.sole.messages.first.content,
                    Loader::LlmPrompts::OUTPUT_CONTRACT
    assert_requested request, times: 1
  end

  test "#load should request a schema that accepts empty publication dates" do
    payload = nil
    stub_request(:post, "https://api.openai.com/v1/responses").to_return do |http|
      payload = JSON.parse(http.body)
      { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
    end

    Loader::LlmLoader.new(feed).load

    schema = JSONSchemer.schema(payload.dig("text", "format", "schema"))
    assert schema.valid?({ "items" => [original_item] })
    assert_not schema.valid?({ "items" => [original_item.except("published_at")] })
  end

  test "#load should include schema-valid examples for retrieval, original content, answers, transformations, and no results" do
    payload = nil
    stub_request(:post, "https://api.openai.com/v1/responses").to_return do |http|
      payload = JSON.parse(http.body)
      { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
    end

    Loader::LlmLoader.new(feed).load

    system = payload.fetch("instructions")
    examples = system.lines.grep(/^\{"items":/).map { |line| JSON.parse(line) }
    schema = JSONSchemer.schema(payload.dig("text", "format", "schema"))
    assert_equal 5, examples.size
    assert schema.valid?(examples[0]), "Retrieved post example must match the provider schema"
    assert schema.valid?(examples[1]), "Original content example must match the provider schema"
    assert schema.valid?(examples[2]), "Synthesized answer example must match the provider schema"
    assert schema.valid?(examples[3]), "Supplied-text transformation example must match the provider schema"
    assert schema.valid?(examples[4]), "Empty result example must match the provider schema"
    assert_equal "https://example.com/posts/garden", examples[0].fetch("items").sole.fetch("source_url")
    assert_nil examples[1].fetch("items").sole.fetch("source_url")
    assert_nil examples[2].fetch("items").sole.fetch("source_url")
    assert_includes examples[2].fetch("items").sole.fetch("body"), "https://example.com/posts/garden"
    assert_nil examples[3].fetch("items").sole.fetch("source_url")
    assert_equal({ "items" => [] }, examples[4])
  end

  test "#load should use the effective schema limit in the assembled instructions" do
    feed.update!(params: feed.params.merge("max_items" => 2))
    payload = nil
    stub_request(:post, "https://api.openai.com/v1/responses").to_return do |http|
      payload = JSON.parse(http.body)
      { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
    end

    Loader::LlmLoader.new(feed).load

    system = payload.fetch("instructions")
    assert_equal ["Return at most 2 items."], system.scan(/Return at most \d+ items\./)
    assert_equal 2, payload.dig("text", "format", "schema", "properties", "items", "maxItems")
    assert_equal "Feed request — what to follow and how to present it:\n\nA daily roundup\n",
                 feed.llm_chats.sole.messages.second.content
  end

  test "#load should pass undated original content to the processor" do
    feed.params = { "prompt" => "Write a short story" }
    output = { "items" => [original_item] }
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return_json(body: completed_response(content: output.to_json))

    freeze_time do
      content = Loader::LlmLoader.new(feed).load
      entry = feed.processor_instance(content).process.entries.sole

      assert_equal original_item, entry.raw_data
      assert_equal Time.current, entry.published_at
      assert feed.llm_chats.sole.succeeded?
    end
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

  test "#load should supply a fresh UTC reference time for each run and honor requested timezones" do
    feed.params = { "prompt" => "Summarize today's news in Asia/Tokyo" }
    payloads = []
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do |http|
      payloads << JSON.parse(http.body)
      { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
    end
    loader = Loader::LlmLoader.new(feed)

    travel_to Time.iso8601("2026-09-21T00:30:00+09:00") do
      loader.load
      assert_equal Time.current, feed.llm_chats.sole.started_at
      travel 1.day
      loader.load
    end

    first_system = payloads.first.fetch("instructions")
    second_system = payloads.last.fetch("instructions")
    assert_includes first_system, "Reference time for this run (UTC): 2026-09-20T15:30:00Z"
    assert_includes second_system, "Reference time for this run (UTC): 2026-09-21T15:30:00Z"
    assert_not_includes second_system, "2026-09-20T15:30:00Z"
    assert_includes first_system, "convert the reference time to the requested timezone before interpreting"
    assert_includes first_system, "When no timezone is specified, use UTC."
    assert_equal payloads.first.fetch("input"), payloads.last.fetch("input")
    assert_includes feed.llm_chats.first.messages.second.content, feed.source_input
    assert_not_includes first_system, feed.source_input
    assert_requested request, times: 2
  end

  test "#load should request and accept transformations of supplied text without a source URL" do
    feed.params = { "prompt" => "Translate this text into French: Hello, world!" }
    item = original_item.merge("body" => "Bonjour, monde !")
    payload = nil
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return do |http|
      payload = JSON.parse(http.body)
      {
        body: completed_response(content: { "items" => [item] }.to_json).to_json,
        headers: { "Content-Type" => "application/json" }
      }
    end

    content = Loader::LlmLoader.new(feed).load
    entry = feed.processor_instance(content).process.entries.sole

    assert_includes payload.fetch("instructions"), "return the transformed text with source_url null;"
    assert_equal item, entry.raw_data
    assert feed.llm_chats.sole.succeeded?
    assert_requested request, times: 1
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
    response = completed_response(content: "invalid JSON")
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)
    loader = Loader::LlmLoader.new(feed)

    result = loader.load

    assert_equal "invalid JSON", result.content
    assert feed.llm_chats.sole.running?
    assert_requested request, times: 1
  end

  test "#load should send the configured ten-item limit that the processor also enforces" do
    feed.update!(params: feed.params.merge("max_items" => 10))
    item = {
      "body" => "A source post", "source_url" => "https://example.com/post",
      "title" => "", "supplementary" => [], "images" => [], "published_at" => ""
    }
    items = Array.new(10) { |index| item.merge("source_url" => "https://example.com/post/#{index}") }
    output = { "items" => items }
    response = completed_response(content: output.to_json)
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

      error = assert_raises(Loader::LlmLoader::ExecutionLimitExceeded) { loader.load }

      assert_kind_of LlmExecution::DeadlineExceeded, error.cause
      chat = feed.llm_chats.sole
      assert chat.interrupted?
      assert_equal "deadline_exceeded", chat.error_category
      assert_equal 1, chat.ruby_llm_usages.count
      assert_requested request, times: 1
    end
  end

  test "#load should keep connection timeouts as request errors without retrying" do
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_timeout

    error = assert_raises(Loader::Error) { Loader::LlmLoader.new(feed).load }

    assert_instance_of Loader::Error, error
    assert_equal "AI request failed. Please try again later.", error.message
    assert_kind_of Faraday::ConnectionFailed, error.cause
    assert_kind_of Net::OpenTimeout, error.cause.cause
    chat = feed.llm_chats.sole
    assert chat.failed?
    assert_equal "Faraday::ConnectionFailed", chat.error_category
    assert_requested request, times: 1
  end

  test "#load should classify read timeouts as execution limits without retrying" do
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_raise(Net::ReadTimeout)

    error = assert_raises(Loader::LlmLoader::ExecutionLimitExceeded) { Loader::LlmLoader.new(feed).load }

    assert_equal "AI request exceeded its deadline.", error.message
    assert_kind_of Faraday::TimeoutError, error.cause
    assert_kind_of Net::ReadTimeout, error.cause.cause
    assert feed.llm_chats.sole.failed?
    assert_requested request, times: 1
  end

  test "#load should keep non-timeout connection failures as request errors" do
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_raise(SocketError)

    error = assert_raises(Loader::Error) { Loader::LlmLoader.new(feed).load }

    assert_instance_of Loader::Error, error
    assert_equal "AI request failed. Please try again later.", error.message
    assert_kind_of Faraday::ConnectionFailed, error.cause
    assert_kind_of SocketError, error.cause.cause
    assert feed.llm_chats.sole.failed?
    assert_requested request, times: 1
  end

  test "#load should translate provider failures without retrying" do
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return_json(status: 429, body: { error: { message: "Rate limited", type: "rate_limit_error" } })
    loader = Loader::LlmLoader.new(feed)

    error = assert_raises(Loader::Error) { loader.load }

    assert_instance_of Loader::Error, error
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
    response["output"] = Array.new(17) do |index|
      { "type" => "web_search_call", "id" => "search_#{index}", "status" => "completed" }
    end + response["output"].select { |item| item["type"] == "message" }
    request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)

    error = assert_raises(Loader::LlmLoader::ExecutionLimitExceeded) { Loader::LlmLoader.new(feed).load }

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

  def original_item
    {
      "body" => "The last star blinked, and the astronomer waved back.",
      "source_url" => nil,
      "title" => "",
      "supplementary" => [],
      "images" => [],
      "published_at" => ""
    }
  end

  def completed_response(content: nil)
    response = JSON.parse(file_fixture("llm_transcripts/completed.json").read)
    return response if content.nil?

    response["output"].select! { |part| part["type"] == "message" }
    response["output"].sole["content"].sole.merge!("text" => content, "annotations" => [])
    response
  end
end
