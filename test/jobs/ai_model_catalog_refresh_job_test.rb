require "test_helper"

class AiModelCatalogRefreshJobTest < ActiveJob::TestCase
  include OpenaiModelsTestHelpers

  def openai_credential
    @openai_credential ||= create(:ai_credential, :active, provider: "openai",
                                                            available_models: [{ "id" => "saved-model" }])
  end

  test "#perform should update the snapshot without changing credential validation" do
    original = openai_credential.attributes.except("available_models", "models_refreshed_at", "updated_at")
    stub_openai_models(key: openai_credential.credential_data["api_key"])
    run = openai_credential.refresh_models_async(force: true)
    assert_enqueued_with(job: AiModelCatalogRefreshJob, args: [run])
    assert_enqueued_with(job: AiModelCatalogTimeoutJob, args: [run], at: run.deadline_at)

    AiModelCatalogRefreshJob.perform_now(run)

    assert_predicate run.reload, :succeeded?
    assert_not openai_credential.reload.models_refreshing?
    assert openai_credential.supports_model?("future-openai-model")
    assert_equal original, openai_credential.attributes.slice(*original.keys)
  end
end
