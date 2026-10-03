require "test_helper"

class Processor::LlmProcessorTest < ActiveSupport::TestCase
  test "#process should retain an item whose source is a homepage" do
    feed = build(:feed, feed_profile_key: "llm", params: { "prompt" => "Find an interesting website" })
    raw_data = { items: [{ body: "An interesting website", source_url: "https://example.com/", published_at: nil, images: [] }] }.to_json

    entry = Processor::LlmProcessor.new(feed, raw_data).process.entries.sole

    assert_equal "https://example.com/", entry.uid
    assert_equal "An interesting website", entry.raw_data["body"]
  end
end
