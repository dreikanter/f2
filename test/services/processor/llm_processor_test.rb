require "test_helper"

class Processor::LlmProcessorTest < ActiveSupport::TestCase
  def feed
    @feed ||= build(:feed, feed_profile_key: "llm", search_credential: nil, params: { "prompt" => "A daily roundup" })
  end

  def process(json)
    feed.processor_instance(json).process
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
  end

  test "#process should accept ten items and reject an oversized response" do
    items = Array.new(10) do |index|
      { "source_url" => "https://example.com/post/#{index}", "body" => "Post #{index}" }
    end

    assert_equal items, process({ items: items }.to_json).entries.map(&:raw_data)

    error = assert_raises(Processor::LlmProcessor::InvalidOutput) do
      process({ items: items + [{ "source_url" => "https://example.com/post/10", "body" => "Extra post" }] }.to_json)
    end
    assert_equal "AI response does not match the output schema.", error.message
  end

  test "#process should derive a digest uid only from an explicit null source_url" do
    freeze_time do
      result = process('{"items":[{"source_url":null,"body":"Daily roundup"}]}')

      assert_equal "digest:#{Time.current.utc.to_date.iso8601}", result.entries.sole.uid
    end
  end

  test "#process should leave unusable permalinks for the workflow to drop and count" do
    result = process('{"items":[{"source_url":"https://example.com/","body":"Homepage"}]}')

    assert result.recognized?
    assert_nil result.entries.sole.uid
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
  end

  test "#process should reject invalid envelopes instead of returning an empty success" do
    ["null", "[]", "{}", '{"items":null}', '{"items":{}}', '{"items":[],"extra":true}'].each do |json|
      assert_raises(Processor::LlmProcessor::InvalidOutput, json) { process(json) }
    end
  end

  test "#process should reject the whole response when any item violates the schema" do
    invalid_items = [
      nil,
      { "source_url" => "https://example.com/post" },
      { "body" => "Missing source_url" },
      { "source_url" => nil, "body" => 123 },
      { "source_url" => nil, "body" => "Post", "images" => [123] },
      { "source_url" => nil, "body" => "Post", "extra" => true }
    ]

    invalid_items.each do |item|
      json = { items: [{ source_url: "https://example.com/valid", body: "Valid post" }, item] }.to_json

      error = assert_raises(Processor::LlmProcessor::InvalidOutput) { process(json) }
      assert_equal "AI response does not match the output schema.", error.message
    end
  end
end
