require "test_helper"

class AiCredentialValidationJobTest < ActiveJob::TestCase
  include OpenaiModelsTestHelpers

  def openai_credential
    @openai_credential ||= create(:ai_credential)
  end

  test "#perform should validate OpenAI in one free request without saving its listing" do
    freeze_time do
      request = stub_openai_models(key: openai_credential.credential_data["api_key"])
      run = openai_credential.validate_async(AiCredentialValidationJob)
      assert_enqueued_with(job: ProviderCredentialValidationTimeoutJob, args: [run], at: run.deadline_at)

      assert_no_difference "LlmUsage.count" do
        perform_enqueued_jobs(only: AiCredentialValidationJob)
      end

      assert_predicate run.reload, :succeeded?
      assert_predicate openai_credential.reload, :active?
      assert_empty openai_credential.available_models
      assert_nil openai_credential.models_refreshed_at
      assert_equal Time.current, openai_credential.last_validated_at
      assert_requested request, times: 1
      assert_not_requested :post, /./
    end
  end

  test "#perform should leave a newly validated key ready for a separate catalog refresh" do
    request = stub_openai_models(key: openai_credential.credential_data.fetch("api_key"))
    validation_run = openai_credential.validate_async(AiCredentialValidationJob)
    perform_enqueued_jobs(only: AiCredentialValidationJob)

    assert_predicate validation_run.reload, :succeeded?
    assert_empty openai_credential.reload.available_models
    assert_no_enqueued_jobs(only: AiModelCatalogRefreshJob)

    refresh_run = openai_credential.refresh_models_async(force: true)
    perform_enqueued_jobs(only: AiModelCatalogRefreshJob)

    assert_predicate refresh_run.reload, :succeeded?
    assert_equal %w[gpt-5.6-luna future-openai-model text-embedding-3-small], openai_credential.reload.available_models.pluck("id")
    assert_requested request, times: 2
  end
end
