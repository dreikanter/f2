require "test_helper"

class AiModelCatalogRefreshJobTest < ActiveJob::TestCase
  setup do
    stub_request(:get, PublishedModelTasks::URL).to_return(body: "{}")
  end

  def credential
    @credential ||= create(:ai_credential, :active, provider: "openai",
                            available_models: [{ "id" => "saved-model" }],
                            credential_data: { "api_key" => "catalog-test-key" })
  end

  def refresh_run
    @refresh_run ||= credential.refresh_models_async(force: true)
  end

  def stub_models(status: 200, ids: ["new-model"], &block)
    stub_request(:get, "https://api.openai.com/v1/models")
      .with(headers: { "Authorization" => "Bearer catalog-test-key" })
      .to_return do
        block&.call
        { status: status, body: { data: ids.map { |id| { id: id, object: "model", owned_by: "openai" } } }.to_json,
          headers: { "Content-Type" => "application/json" } }
      end
  end

  test "#perform should discover new models and metadata without inference or changing credential state and saved feeds" do
    feed = create(:feed, user: credential.user, ai_credential: credential, ai_model: "saved-model")
    request = stub_models
    stub_request(:get, PublishedModelMetadata::URL).to_return(body: {
      openai: { models: { "new-model" => { tool_call: false, structured_output: false } } }
    }.to_json)

    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      assert_no_difference [-> { LlmUsage.count }, -> { Event.count }] do
        AiModelCatalogRefreshJob.perform_now(refresh_run)
      end
    end

    assert_predicate refresh_run.reload, :succeeded?
    assert_predicate credential.reload, :active?
    assert_equal ["new-model"], credential.supported_models.pluck("id")
    assert_same false, credential.model_metadata("new-model")["structured_output"]
    assert_not_nil credential.models_refreshed_at
    assert_equal "saved-model", feed.reload.ai_model
    assert_equal "saved-model", feed.effective_ai_model
    assert_requested request, times: 1
    assert_not_requested :post, /./
    assert_not_includes refresh_run.context.to_json, "catalog-test-key"
  end

  test "#perform should retain the snapshot and active credential on listing failure" do
    request = stub_models(status: 401)
    original = credential.attributes

    AiModelCatalogRefreshJob.perform_now(refresh_run)

    assert_predicate refresh_run.reload, :failed?
    assert_equal original, credential.reload.attributes
    assert_requested request, times: 1
    assert_not_requested :get, PublishedModelMetadata::URL
  end

  test "#perform should allow discovery when published metadata is unavailable" do
    stub_models
    stub_request(:get, PublishedModelMetadata::URL).to_timeout
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      AiModelCatalogRefreshJob.perform_now(refresh_run)
    end

    assert_predicate refresh_run.reload, :succeeded?
    assert credential.reload.supports_model?("new-model")
    assert_empty credential.model_metadata("new-model")
  end

  test "#perform should retain cached published metadata during an outage" do
    stub_models
    request = stub_request(:get, PublishedModelMetadata::URL).to_return(body: {
      openai: { models: { "new-model" => { tool_call: false } } }
    }.to_json).then.to_return(status: 503)

    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      AiModelCatalogRefreshJob.perform_now(refresh_run)
      travel 25.hours
      AiModelCatalogRefreshJob.perform_now(credential.refresh_models_async(force: true))
    end

    assert_same false, credential.reload.model_metadata("new-model")["tool_call"]
    assert_requested request, times: 2
  end

  test "#perform should clear capabilities and prices removed from a successful catalog" do
    credential.update!(available_models: [{ "id" => "new-model", "metadata" => {
      "source" => "models.dev", "tool_call" => false, "structured_output" => false,
      "output_modalities" => ["image"], "pricing" => { "input" => 1 }
    } }])
    stub_models
    stub_request(:get, PublishedModelMetadata::URL).to_return(body: "{}")

    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      AiModelCatalogRefreshJob.perform_now(refresh_run)
    end

    assert_predicate refresh_run.reload, :succeeded?
    assert credential.reload.supports_model?("new-model")
    assert_empty credential.model_metadata("new-model")
  end

  test "#perform should expire cached capabilities during a prolonged outage and preserve saved selections" do
    feed = create(:feed, user: credential.user, ai_credential: credential, ai_model: "saved-model")
    stub_models
    request = stub_request(:get, PublishedModelMetadata::URL).to_return(body: {
      openai: { models: { "new-model" => {
        tool_call: false, structured_output: false, modalities: { output: ["image"] }, cost: { input: 1 }
      } } }
    }.to_json).then.to_return(status: 503)

    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      AiModelCatalogRefreshJob.perform_now(refresh_run)
      travel 6.days
      AiModelCatalogRefreshJob.perform_now(credential.refresh_models_async(force: true))
      assert_same false, credential.reload.model_metadata("new-model")["tool_call"]
      assert_empty credential.supported_models

      travel 25.hours
      AiModelCatalogRefreshJob.perform_now(credential.refresh_models_async(force: true))
    end

    assert_predicate credential.reload, :active?
    assert credential.supports_model?("new-model")
    assert_empty credential.model_metadata("new-model")
    assert_equal "saved-model", feed.reload.effective_ai_model
    assert_requested request, times: 3
    assert_not_requested :post, /./
  end

  test "#perform should discard late results after the key changes" do
    stub_models { AiCredential.find(credential.id).update!(credential_data: { "api_key" => "replacement" }) }
    stub_request(:get, PublishedModelMetadata::URL).to_return(body: "{}")

    AiModelCatalogRefreshJob.perform_now(refresh_run)

    assert_predicate refresh_run.reload, :failed?
    assert_equal ["saved-model"], credential.reload.available_models.pluck("id")
  end

  test "#perform should discard results after a newer refresh supersedes it" do
    stub_models { OperationRun.start!(subject: AiCredential.find(credential.id), kind: :models_refresh, timeout: 15.minutes) }
    stub_request(:get, PublishedModelMetadata::URL).to_return(body: "{}")

    AiModelCatalogRefreshJob.perform_now(refresh_run)

    assert_predicate refresh_run.reload, :superseded?
    assert_equal ["saved-model"], credential.reload.available_models.pluck("id")
  end

  test "#perform should expire an old queued job without contacting the provider" do
    current_run = refresh_run
    travel 16.minutes

    AiModelCatalogRefreshJob.perform_now(current_run)

    assert_predicate current_run.reload, :timed_out?
    assert_predicate credential.reload, :active?
    assert_not_requested :any, /./
  end

  test "#refresh_models_async should deduplicate running work and honor freshness unless forced" do
    current_run = refresh_run
    assert_no_enqueued_jobs { assert_equal current_run, credential.refresh_models_async(force: true) }
    current_run.succeed! { |record| record.update!(models_refreshed_at: Time.current) }
    assert_no_enqueued_jobs { assert_nil credential.refresh_models_async }
    assert_enqueued_with(job: AiModelCatalogRefreshJob) { credential.refresh_models_async(force: true) }
  end

  test "#refresh_models_async should refresh stale catalogs and skip inactive credentials" do
    credential.update!(models_refreshed_at: 2.days.ago)
    assert_enqueued_with(job: AiModelCatalogRefreshJob) { credential.refresh_models_async }
    credential.update!(state: :inactive)
    assert_no_enqueued_jobs { assert_nil credential.refresh_models_async(force: true) }
  end

  test "#perform should keep completed runs settled when the timeout job arrives" do
    refresh_run.succeed!
    AiModelCatalogTimeoutJob.perform_now(refresh_run)
    assert_predicate refresh_run.reload, :succeeded?
  end
  test "#perform should retain the snapshot on an empty listing" do
    stub_models(ids: [])
    AiModelCatalogRefreshJob.perform_now(refresh_run)
    assert_predicate refresh_run.reload, :failed?
    assert_equal ["saved-model"], credential.reload.available_models.pluck("id")
  end

  test "#perform should enrich a provider listing with free task metadata while preserving saved models" do
    feed = create(:feed, user: credential.user, ai_credential: credential, ai_model: "gpt-image-1.5")
    ids = %w[text-embedding-3-small gpt-image-1.5 gpt-realtime-2.1 future-model]
    stub_models(ids: ids)
    stub_request(:get, PublishedModelMetadata::URL).to_return(body: {
      openai: { models: ids.to_h { |id| [id, { modalities: { output: ["text", "image"] } }] } }
    }.to_json)
    task_request = stub_request(:get, PublishedModelTasks::URL).to_return(body: {
      "text-embedding-3-small" => { litellm_provider: "openai", mode: "embedding" },
      "gpt-image-1.5" => { litellm_provider: "openai", mode: "image_generation" },
      "gpt-realtime-2.1" => { litellm_provider: "openai", mode: "realtime" },
      "not-listed" => { litellm_provider: "openai", mode: "chat" }
    }.to_json)

    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      assert_no_difference -> { LlmUsage.count } do
        AiModelCatalogRefreshJob.perform_now(refresh_run)
      end
    end

    assert_predicate refresh_run.reload, :succeeded?
    assert credential.reload.active?
    assert_equal ids, credential.available_models.pluck("id")
    assert_equal ["future-model"], credential.supported_models.pluck("id")
    assert_equal "gpt-image-1.5", feed.reload.effective_ai_model
    assert_equal "models.dev", credential.model_metadata("gpt-image-1.5")["source"]
    assert_equal "litellm", credential.model_metadata("gpt-image-1.5").dig("task", "source")
    assert_requested task_request, times: 1
    assert_not_requested :post, /./
  end

  test "#perform should retain cached capabilities during their outage while applying fresh task metadata" do
    stub_models
    metadata_request = stub_request(:get, PublishedModelMetadata::URL).to_return(body: {
      openai: { models: { "new-model" => { tool_call: false } } }
    }.to_json).then.to_return(status: 503)
    task_request = stub_request(:get, PublishedModelTasks::URL).to_return(body: "{}").then.to_return(body: {
      "new-model" => { litellm_provider: "openai", mode: "embedding" }
    }.to_json)

    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      AiModelCatalogRefreshJob.perform_now(refresh_run)
      travel 25.hours
      AiModelCatalogRefreshJob.perform_now(credential.refresh_models_async(force: true))
    end

    assert_same false, credential.reload.model_metadata("new-model")["tool_call"]
    assert_equal "embedding", credential.model_metadata("new-model").dig("task", "mode")
    assert_empty credential.supported_models
    assert_requested metadata_request, times: 2
    assert_requested task_request, times: 2
  end

  test "#perform should refresh capabilities and keep new models selectable during a task catalog outage" do
    stub_models
    stub_request(:get, PublishedModelMetadata::URL).to_return(body: {
      openai: { models: { "new-model" => { tool_call: false } } }
    }.to_json)
    stub_request(:get, PublishedModelTasks::URL).to_timeout

    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      AiModelCatalogRefreshJob.perform_now(refresh_run)
    end

    assert_predicate refresh_run.reload, :succeeded?
    assert_same false, credential.reload.model_metadata("new-model")["tool_call"]
    assert_nil credential.model_metadata("new-model")["task"]
    assert credential.supports_model?("new-model")
  end

  test "#perform should clear task classifications removed from a successful catalog" do
    credential.update!(available_models: [{ "id" => "new-model", "metadata" => { "task" => { "source" => "litellm", "mode" => "embedding" } } }])
    stub_models
    stub_request(:get, PublishedModelMetadata::URL).to_return(body: "{}")

    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      AiModelCatalogRefreshJob.perform_now(refresh_run)
    end

    assert credential.reload.supports_model?("new-model")
    assert_nil credential.model_metadata("new-model")["task"]
  end
end
