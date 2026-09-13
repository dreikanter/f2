require "test_helper"

class AiModelCatalogRefreshJobTest < ActiveJob::TestCase
  include OpenaiModelsTestHelpers

  def openai_credential
    @openai_credential ||= create(
      :ai_credential,
      :active,
      available_models: [{ "id" => "saved-model" }],
      models_refreshed_at: 1.day.ago
    )
  end

  test "#perform should update the snapshot without changing credential validation" do
    freeze_time do
      original = openai_credential.attributes.except("available_models", "models_refreshed_at", "updated_at")
      request = stub_openai_models(key: openai_credential.credential_data["api_key"])
      run = openai_credential.refresh_models_async(force: true)
      assert_enqueued_with(job: AiModelCatalogTimeoutJob, args: [run], at: run.deadline_at)

      perform_enqueued_jobs(only: AiModelCatalogRefreshJob)

      assert_predicate run.reload, :succeeded?
      assert_equal %w[gpt-5.6-luna future-openai-model text-embedding-3-small], openai_credential.reload.available_models.pluck("id")
      assert_equal Time.current, openai_credential.models_refreshed_at
      assert_equal original, openai_credential.attributes.slice(*original.keys)
      assert_requested request, times: 1
    end
  end
end
