require "test_helper"

class Processor::LlmProcessorTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "llm", search_credential: nil, params: { "prompt" => "A daily roundup" })
  end

  def chat
    @chat ||= create(:llm_chat, feed: feed, user: feed.user)
  end

  def process(json)
    payload = LlmResult.new(content: json, chat: chat)
    feed.processor_instance(payload).process
  end

  test "#process should build pending entries from validated JSON and preserve their content" do
    items = [
      {
        "uid" => "model-generated-id",
        "source_url" => "https://Example.com/post/1/?utm_source=x",
        "title" => "First post",
        "body" => "Post content",
        "supplementary" => ["Additional context"],
        "images" => ["https://example.com/image.jpg"],
        "published_at" => "2026-04-15T12:30:00Z"
      },
      { "source_url" => "https://example.com/post/2", "body" => "Second post" }
    ]

    freeze_time do
      result = process({ items: items }.to_json)

      assert chat.reload.succeeded?
      assert result.recognized?
      assert_equal ["https://example.com/post/1", "https://example.com/post/2"], result.entries.map(&:uid)
      assert_equal items, result.entries.map(&:raw_data)
      assert_equal Time.zone.parse("2026-04-15T12:30:00Z"), result.entries.first.published_at
      assert_equal Time.current, result.entries.last.published_at
      result.entries.each do |entry|
        assert_equal feed, entry.feed
        assert entry.pending?
        assert entry.new_record?
      end
    end
  end

  test "#process should recognize a valid empty response" do
    result = process('{"items":[]}')

    assert result.recognized?
    assert_empty result.entries
    assert chat.reload.succeeded?
  end

  test "#process should reject the whole response before deduplication at the configured limit" do
    feed.params["max_items"] = 1
    item = { source_url: "https://example.com/post", body: "Post" }

    assert_raises(Processor::LlmProcessor::InvalidOutput) do
      process({ items: [item, item] }.to_json)
    end

    assert chat.reload.failed?
    assert_empty feed.feed_entries
  end

  test "#process should allow an empty response with a one-item limit" do
    feed.params["max_items"] = 1

    assert_empty process('{"items":[]}').entries
  end

  test "#process should accept ten items" do
    items = Array.new(10) do |index|
      { "source_url" => "https://example.com/post/#{index}", "body" => "Post #{index}" }
    end

    assert_equal items, process({ items: items }.to_json).entries.map(&:raw_data)
    assert chat.reload.succeeded?
  end

  test "#process should reject an oversized response" do
    items = Array.new(10) do |index|
      { "source_url" => "https://example.com/post/#{index}", "body" => "Post #{index}" }
    end

    error = assert_raises(Processor::LlmProcessor::InvalidOutput) do
      process({ items: items + [{ "source_url" => "https://example.com/post/10", "body" => "Extra post" }] }.to_json)
    end
    assert_equal "AI response does not match the output schema.", error.message
  end

  test "#process should accept output when the stored response limit is zero" do
    feed.update_column(:params, feed.params.merge("max_items" => 0))
    feed.reload
    item = { "source_url" => "https://example.com/post", "body" => "Post" }

    assert_equal item, process({ items: [item] }.to_json).entries.sole.raw_data
    assert chat.reload.succeeded?
  end

  test "#process should enforce the default limit when the stored response limit is too large" do
    feed.update_column(:params, feed.params.merge("max_items" => 11))
    feed.reload
    items = Array.new(11) do |index|
      { "source_url" => "https://example.com/post/#{index}", "body" => "Post #{index}" }
    end

    assert_raises(Processor::LlmProcessor::InvalidOutput) { process({ items: items }.to_json) }

    assert chat.reload.failed?
    assert_empty feed.feed_entries
  end

  test "#process should assign distinct system UUIDs to original items even on the same day" do
    freeze_time do
      result = process({ items: [
        { source_url: nil, body: "First story", uid: "invented-id" },
        { source_url: nil, body: "Second story", uid: "invented-id" }
      ] }.to_json)

      first, second = result.entries
      assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, first.uid)
      assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, second.uid)
      assert_not_equal first.uid, second.uid
    end
  end

  test "#process should leave blank and malformed sources unidentified" do
    result = process({ items: [
      { source_url: "", body: "Blank" },
      { source_url: "not a URL", body: "Malformed" }
    ] }.to_json)

    assert_nil result.entries.first.uid
    assert_nil result.entries.last.uid
  end

  test "#process should leave unusable permalinks for the workflow to drop and count" do
    result = process('{"items":[{"source_url":"https://example.com/","body":"Homepage"}]}')

    assert result.recognized?
    assert_nil result.entries.sole.uid
  end

  test "#process should use the current time when the source publication date is empty" do
    freeze_time do
      result = process('{"items":[{"source_url":"https://example.com/post","body":"Post","published_at":""}]}')
      entry = result.entries.sole

      assert_equal Time.current, entry.published_at
      assert_equal "", entry.raw_data.fetch("published_at")
      assert chat.reload.succeeded?
    end
  end

  test "#process should use the current time for an unreadable publication date" do
    freeze_time do
      result = process('{"items":[{"source_url":"https://example.com/post","body":"Post","published_at":"not a date"}]}')

      assert_equal Time.current, result.entries.sole.published_at
    end
  end

  test "#process should reject malformed JSON without exposing response content in the error" do
    error = assert_raises(Processor::LlmProcessor::InvalidOutput) { process('{"private-content":') }

    assert_equal "AI response is not valid JSON.", error.message
    assert_nil error.cause
    assert chat.reload.failed?
    assert_equal "Processor::LlmProcessor::InvalidOutput", chat.error_category
  end

  {
    "null" => "null",
    "an array" => "[]",
    "missing items" => "{}",
    "null items" => '{"items":null}',
    "object items" => '{"items":{}}',
    "extra fields" => '{"items":[],"extra":true}'
  }.each do |description, json|
    test "#process should reject #{description} as an invalid envelope" do
      assert_raises(Processor::LlmProcessor::InvalidOutput) { process(json) }

      assert chat.reload.failed?
    end
  end

  {
    "null item" => nil,
    "missing body" => { "source_url" => "https://example.com/post" },
    "missing source_url" => { "body" => "Missing source_url" },
    "numeric body" => { "source_url" => nil, "body" => 123 },
    "non-string image" => { "source_url" => nil, "body" => "Post", "images" => [123] },
    "extra item field" => { "source_url" => nil, "body" => "Post", "extra" => true }
  }.each do |description, item|
    test "#process should reject the whole response for #{description}" do
      json = { items: [{ source_url: "https://example.com/valid", body: "Valid post" }, item] }.to_json

      error = assert_raises(Processor::LlmProcessor::InvalidOutput) { process(json) }

      assert_equal "AI response does not match the output schema.", error.message
      assert chat.reload.failed?
      assert_empty feed.feed_entries
    end
  end

  test "#process should reject valid output when its chat expires before processing" do
    freeze_time do
      payload = LlmResult.new(content: '{"items":[]}', chat: chat)
      travel_to chat.deadline_at

      error = assert_raises(LlmResult::LifecycleError) { feed.processor_instance(payload).process }

      assert_equal "AI extraction is no longer active.", error.message
      assert chat.reload.interrupted?
      assert_equal "deadline_exceeded", chat.error_category
    end
  end

  test "#process should preserve a terminal outcome written after loading" do
    payload = LlmResult.new(content: '{"items":[]}', chat: chat)
    LlmChat.find(chat.id).finish!(status: :failed, error_category: "original_failure")

    assert_raises(LlmResult::LifecycleError) { feed.processor_instance(payload).process }

    assert chat.reload.failed?
    assert_equal "original_failure", chat.error_category
  end

  test "#process should settle expired invalid output as interrupted" do
    freeze_time do
      payload = LlmResult.new(content: "invalid JSON", chat: chat)
      travel_to chat.deadline_at

      assert_raises(Processor::LlmProcessor::InvalidOutput) { feed.processor_instance(payload).process }

      assert chat.reload.interrupted?
      assert_equal "deadline_exceeded", chat.error_category
    end
  end
end
