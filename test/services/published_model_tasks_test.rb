require "test_helper"

class PublishedModelTasksTest < ActiveSupport::TestCase
  def catalog
    {
      "new-model" => { "litellm_provider" => "openai", "mode" => "embedding", "input_cost_per_token" => 10 },
      "legacy-model" => { "litellm_provider" => "text-completion-openai", "mode" => "completion" },
      "claude-new" => { "litellm_provider" => "anthropic", "mode" => "chat" },
      "openrouter/openai/new-model" => { "litellm_provider" => "openrouter", "mode" => "chat" },
      "moonshot/kimi-new" => { "litellm_provider" => "moonshot", "mode" => "chat" },
      "kimi-new" => { "litellm_provider" => "openai", "mode" => "embedding" }
    }
  end

  test "#lookup should isolate providers and exact model IDs without importing prices or capabilities" do
    request = stub_request(:get, PublishedModelTasks::URL).to_return(body: catalog.to_json)
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      tasks = PublishedModelTasks.new
      assert_equal({ "source" => "litellm", "mode" => "embedding" }, tasks.lookup("openai", "new-model"))
      assert_equal "completion", tasks.lookup("openai", "legacy-model")["mode"]
      assert_equal "chat", tasks.lookup("anthropic", "claude-new")["mode"]
      assert_equal "chat", tasks.lookup("openrouter", "openai/new-model")["mode"]
      assert_equal "chat", tasks.lookup("moonshot", "kimi-new")["mode"]
      assert_nil tasks.lookup("anthropic", "new-model")
      assert_nil tasks.lookup("openrouter", "new-model")
      assert_nil tasks.lookup("moonshotai-cn", "kimi-new")
      assert_nil tasks.lookup("openai", "new-model-2026-09-06")
      assert_nil tasks.lookup("openai", "new-model:free")
      PublishedModelTasks.new.lookup("openai", "new-model")
    end
    assert_requested request, times: 1
    assert_not_requested :post, /./
  end

  test "#lookup should accept namespaced direct entries but leave conflicting entries unknown" do
    data = catalog.merge("openai/namespaced" => { litellm_provider: "openai", mode: "responses" },
                         "openai/new-model" => { litellm_provider: "openai", mode: "chat" },
                         "openrouter/foreign" => { litellm_provider: "openai", mode: "embedding" })
    stub_request(:get, PublishedModelTasks::URL).to_return(body: data.to_json)
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      tasks = PublishedModelTasks.new
      assert_equal "responses", tasks.lookup("openai", "namespaced")["mode"]
      assert_nil tasks.lookup("openai", "new-model")
      assert_nil tasks.lookup("openrouter", "foreign")
    end
  end

  test "#lookup should retain new task modes and ignore malformed modes" do
    data = [nil, "", " ", [], { mode: "chat" }, "future_task"].each_with_index.to_h do |mode, i|
      ["model-#{i}", { litellm_provider: "openai", mode: mode }]
    end
    stub_request(:get, PublishedModelTasks::URL).to_return(body: data.to_json)
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      tasks = PublishedModelTasks.new
      5.times { |i| assert_nil tasks.lookup("openai", "model-#{i}") }
      assert_equal "future_task", tasks.lookup("openai", "model-5")["mode"]
    end
  end

  test "#lookup should cache tasks independently from capabilities and back off during outages" do
    freeze_time do
      tasks_request = stub_request(:get, PublishedModelTasks::URL).to_return(body: catalog.to_json).then.to_return(status: 503)
      capabilities_request = stub_request(:get, PublishedModelMetadata::URL).to_return(body: {
        openai: { models: { "new-model" => { tool_call: true } } }
      }.to_json)
      Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
        expected = PublishedModelTasks.new.lookup("openai", "new-model")
        assert_same true, PublishedModelMetadata.new.lookup("openai", "new-model")["tool_call"]
        travel 25.hours
        assert_equal expected, PublishedModelTasks.new.lookup("openai", "new-model")
        assert_equal expected, PublishedModelTasks.new.lookup("openai", "new-model")
        assert_same true, PublishedModelMetadata.new.lookup("openai", "new-model")["tool_call"]
        travel 7.days
        assert_nil PublishedModelTasks.new.lookup("openai", "new-model")
        assert_nil PublishedModelTasks.new.lookup("openai", "new-model")
      end
      assert_requested tasks_request, times: 3
      assert_requested capabilities_request, times: 2
    end
  end

  test "#lookup should leave tasks unknown when the catalog is unavailable or malformed" do
    ["broken JSON", "[]", '{"model":"bad entry"}'].each do |body|
      stub_request(:get, PublishedModelTasks::URL).to_return(body: body)
      Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
        assert_nil PublishedModelTasks.new.lookup("openai", "new-model")
      end
    end
  end
end
