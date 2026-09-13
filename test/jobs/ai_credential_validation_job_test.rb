require "test_helper"

class AiCredentialValidationJobTest < ActiveJob::TestCase
  include OpenaiModelsTestHelpers

  def openai_credential
    @openai_credential ||= create(:ai_credential, :active, provider: "openai",
                                                            available_models: [{ "id" => "saved-model" }])
  end

  test "#perform should validate OpenAI and save its free listing in one request" do
    request = stub_openai_models(key: openai_credential.credential_data["api_key"])
    run = openai_credential.validate_async(AiCredentialValidationJob)
    assert_predicate openai_credential.reload, :validating?
    assert_enqueued_with(job: ProviderCredentialValidationTimeoutJob, args: [run], at: run.deadline_at)

    assert_no_difference "LlmUsage.count" do
      AiCredentialValidationJob.perform_now(run)
    end

    assert_predicate run.reload, :succeeded?
    assert_predicate openai_credential.reload, :active?
    assert openai_credential.supports_model?("future-openai-model")
    assert_not_nil openai_credential.models_refreshed_at
    assert_not_nil openai_credential.last_validated_at
    assert_nil openai_credential.last_error
    assert_requested request, times: 1
    assert_not_requested :post, /./
  end
end
