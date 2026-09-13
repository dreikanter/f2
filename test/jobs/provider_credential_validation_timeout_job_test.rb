require "test_helper"

class ProviderCredentialValidationTimeoutJobTest < ActiveJob::TestCase
  test "#perform should settle a new credential to its fallback state" do
    credential = create(:ai_credential)
    run = credential.validate_async(AiCredentialValidationJob)

    ProviderCredentialValidationTimeoutJob.perform_now(run)

    assert_predicate credential.reload, :inactive?
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
    run.succeed! { |current| current.update!(state: :active) }
    original = credential.reload.attributes

    ProviderCredentialValidationTimeoutJob.perform_now(run)

    assert_predicate run.reload, :succeeded?
    assert_equal original, credential.reload.attributes
  end
end
