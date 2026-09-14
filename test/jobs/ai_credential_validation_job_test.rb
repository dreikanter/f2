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
      assert_equal Time.current, openai_credential.last_validated_at
      assert_requested request, times: 1
      assert_not_requested :post, /./
    end
  end
end
