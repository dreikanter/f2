require "test_helper"

class AiCredentialValidationJobTest < ActiveJob::TestCase
  include OpenaiModelsTestHelpers

  def openai_credential
    @openai_credential ||= create(
      :ai_credential,
      :active,
      available_models: [{ "id" => "saved-model" }],
      models_refreshed_at: 1.day.ago
    )
  end

  test "#perform should validate OpenAI and save its free listing in one request" do
    freeze_time do
      request = stub_openai_models(key: openai_credential.credential_data["api_key"])
      run = openai_credential.validate_async(AiCredentialValidationJob)
      assert_enqueued_with(job: ProviderCredentialValidationTimeoutJob, args: [run], at: run.deadline_at)

      assert_no_difference "LlmUsage.count" do
        perform_enqueued_jobs(only: AiCredentialValidationJob)
      end

      assert_predicate run.reload, :succeeded?
      assert_predicate openai_credential.reload, :active?
      assert_equal %w[gpt-5.6-luna future-openai-model text-embedding-3-small], openai_credential.available_models.pluck("id")
      assert_equal Time.current, openai_credential.models_refreshed_at
      assert_equal Time.current, openai_credential.last_validated_at
      assert_requested request, times: 1
    end
  end
end
