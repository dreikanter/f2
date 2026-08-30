require "test_helper"

class ProviderCredentialValidationTimeoutJobTest < ActiveJob::TestCase
  test "#perform should settle a new credential to its fallback state" do
    credential = create(:ai_credential, state: :validating)
    run = create(:operation_run, subject: credential, context: { fallback_state: "inactive" })

    ProviderCredentialValidationTimeoutJob.perform_now(run)

    assert_predicate credential.reload, :inactive?
    assert_predicate run.reload, :timed_out?
  end

  test "#perform should preserve an active credential after an inconclusive run" do
    credential = create(:search_credential, state: :validating)
    run = create(:operation_run, subject: credential, context: { fallback_state: "active" })

    ProviderCredentialValidationTimeoutJob.perform_now(run)

    assert_predicate credential.reload, :active?
    assert_predicate run.reload, :timed_out?
  end

  test "#perform should ignore a superseded run" do
    credential = create(:search_credential, state: :validating)
    run = create(:operation_run, subject: credential, status: :superseded, finished_at: Time.current,
                                 context: { fallback_state: "inactive" })
    original_attributes = credential.attributes.slice("state", "updated_at")

    ProviderCredentialValidationTimeoutJob.perform_now(run)

    assert_equal original_attributes, credential.reload.attributes.slice(*original_attributes.keys)
  end
end
