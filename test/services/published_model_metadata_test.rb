require "test_helper"

class PublishedModelMetadataTest < ActiveSupport::TestCase
  def catalog
    {
      "openai" => { "models" => {
        "new-model" => {
          "tool_call" => false, "structured_output" => true,
          "modalities" => { "output" => ["text"] },
          "limit" => { "context" => 32_000, "output" => 4_096 },
          "cost" => { "input" => 1.5, "output" => 0, "cache_read" => "unknown" }
        }
      } },
      "moonshotai" => { "models" => { "kimi-new" => { "tool_call" => true } } }
    }
  end

  test "#lookup should preserve known false and unknown values and isolate providers and exact IDs" do
    request = stub_request(:get, PublishedModelMetadata::URL).to_return(body: catalog.to_json)
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      metadata = PublishedModelMetadata.new
      entry = metadata.lookup("openai", "new-model")
      assert_equal false, entry["tool_call"]
      assert_equal true, entry["structured_output"]
      assert_equal ["text"], entry["output_modalities"]
      assert_equal 4_096, entry["max_output_tokens"]
      assert_equal({ "input" => 1.5, "output" => 0 }, entry["pricing"])
      assert_nil metadata.lookup("anthropic", "new-model")
      assert_nil metadata.lookup("openai", "new-model-latest")
      assert_equal({ "source" => "models.dev", "tool_call" => true }, metadata.lookup("moonshot", "kimi-new"))
      assert_nil metadata.lookup("openai", "kimi-new")
      PublishedModelMetadata.new.lookup("openai", "new-model")
    end
    assert_requested request, times: 1
    assert_not_requested :post, /./
  end

  test "#lookup should retain a cached catalog on outage and back off repeated refreshes" do
    freeze_time do
      request = stub_request(:get, PublishedModelMetadata::URL)
        .to_return(body: catalog.to_json).then.to_return(status: 503)
      Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
        expected = PublishedModelMetadata.new.lookup("openai", "new-model")
        travel 25.hours
        assert_equal expected, PublishedModelMetadata.new.lookup("openai", "new-model")
        assert_equal expected, PublishedModelMetadata.new.lookup("openai", "new-model")
      end
      assert_requested request, times: 2
    end
  end

  test "#lookup should keep capabilities unknown when metadata cannot be loaded" do
    ["broken JSON", "[]", '{"openai":{}}'].each do |body|
      stub_request(:get, PublishedModelMetadata::URL).to_return(body: body)
      Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
        assert_nil PublishedModelMetadata.new.lookup("openai", "new-model")
      end
    end
  end
end
