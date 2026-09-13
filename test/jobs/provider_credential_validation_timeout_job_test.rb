require "test_helper"

class ProviderCredentialValidationTimeoutJobTest < ActiveJob::TestCase
  test "#perform should time out validation while leaving a new credential inactive" do
    credential = create(:ai_credential)
    run = credential.validate_async(AiCredentialValidationJob)

    ProviderCredentialValidationTimeoutJob.perform_now(run)

    assert_not_predicate credential.reload, :active?
    assert_predicate run.reload, :timed_out?
  end

  test "#perform should preserve an active credential after an inconclusive run" do
    credential = create(:search_credential, :active)
    run = credential.validate_async(SearchCredentialValidationJob)

    ProviderCredentialValidationTimeoutJob.perform_now(run)

    assert_predicate credential.reload, :active?
    assert_predicate run.reload, :timed_out?
  end

  test "#perform should ignore a superseded run" do
    credential = create(:search_credential)
    run = credential.validate_async(SearchCredentialValidationJob)
    current = credential.validate_async(SearchCredentialValidationJob)
    original = credential.attributes

    ProviderCredentialValidationTimeoutJob.perform_now(run)

    assert_predicate run.reload, :superseded?
    assert_predicate current.reload, :running?
    assert_equal original, credential.reload.attributes
  end

  test "#perform should preserve a completed validation" do
    credential = create(:ai_credential)
    run = credential.validate_async(AiCredentialValidationJob)
    run.succeed! { |current| current.update!(active: true) }
    original = credential.reload.attributes

    ProviderCredentialValidationTimeoutJob.perform_now(run)

    assert_predicate run.reload, :succeeded?
    assert_equal original, credential.reload.attributes
  end
end
