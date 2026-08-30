require "test_helper"

class ProviderCredentialValidationTimeoutJobTest < ActiveJob::TestCase
  test "#perform should settle a new credential to its fallback state" do
    run_id = SecureRandom.uuid
    credential = create(:ai_credential, state: :validating,
                                        validation_started_at: 15.minutes.ago,
                                        validation_run_id: run_id)

    ProviderCredentialValidationTimeoutJob.perform_now(
      credential, run_id, "inactive"
    )

    assert credential.reload.inactive?
    assert_nil credential.validation_started_at
    assert_nil credential.validation_run_id
  end

  test "#perform should preserve an active credential after an inconclusive run" do
    run_id = SecureRandom.uuid
    credential = create(:search_credential, state: :validating,
                                            validation_started_at: 15.minutes.ago,
                                            validation_run_id: run_id)

    ProviderCredentialValidationTimeoutJob.perform_now(
      credential, run_id, "active"
    )

    assert credential.reload.active?
  end

  test "#perform should ignore a superseded run" do
    credential = create(:search_credential, state: :validating,
                                            validation_started_at: Time.current,
                                            validation_run_id: SecureRandom.uuid)
    original_attributes = credential.attributes.slice(
      "state", "validation_started_at", "validation_run_id", "updated_at"
    )

    ProviderCredentialValidationTimeoutJob.perform_now(
      credential, SecureRandom.uuid, "inactive"
    )

    assert_equal original_attributes, credential.reload.attributes.slice(*original_attributes.keys)
  end
end
