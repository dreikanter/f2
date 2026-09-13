require "test_helper"

class ProviderCredentialValidationTimeoutJobTest < ActiveJob::TestCase
  test "#perform should time out validation while leaving a new credential inactive" do
    credential = create(:ai_credential)
    run = credential.validate_async(AiCredentialValidationJob)

    travel_to run.deadline_at do
      ProviderCredentialValidationTimeoutJob.perform_now(run)
    end

    assert_not_predicate credential.reload, :active?
    assert_predicate run.reload, :timed_out?
  end

  test "#perform should preserve an active credential after an inconclusive run" do
    credential = create(:search_credential, :active)
    run = credential.validate_async(SearchCredentialValidationJob)

    travel_to run.deadline_at do
      ProviderCredentialValidationTimeoutJob.perform_now(run)
    end

    assert_predicate credential.reload, :active?
    assert_predicate run.reload, :timed_out?
  end
end
