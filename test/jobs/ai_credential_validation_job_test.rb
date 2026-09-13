require "test_helper"

class AiCredentialValidationJobTest < ActiveJob::TestCase
  test "#perform should settle pending validation without invalidating a working key or its feeds" do
    credential = create(:ai_credential, :active, available_models: [{ "id" => "saved-model" }])
    feed = create(:feed, :enabled, user: credential.user, ai_credential: credential)
    original = credential.attributes.except("state", "last_error", "updated_at")
    credential.update!(state: :validating)
    run = OperationRun.start!(subject: credential, kind: :validation, context: { fallback_state: "active" })

    assert_no_enqueued_jobs { AiCredentialValidationJob.perform_now(run) }

    assert_predicate run.reload, :failed?
    assert_predicate credential.reload, :active?
    assert_equal AiModelCatalog::UNAVAILABLE_MESSAGE, credential.last_error
    assert_equal original, credential.attributes.slice(*original.keys)
    assert_predicate feed.reload, :enabled?
    assert_not Event.exists?(subject: credential, type: "ai_credential_deactivated")
    assert_not_requested :any, /./
  end

  test "#validate_async should settle a new credential without starting polling or queued work" do
    credential = create(:ai_credential)

    assert_no_enqueued_jobs { credential.validate_async(AiCredentialValidationJob) }

    assert_predicate credential.reload, :inactive?
    assert_predicate credential.latest_operation_run(:validation), :failed?
    assert_equal AiModelCatalog::UNAVAILABLE_MESSAGE, credential.last_error
    assert_nil credential.last_validated_at
    assert_not_requested :any, /./
  end

  test "#perform should not let a superseded run overwrite a replacement key" do
    credential = create(:ai_credential, :active)
    stale = OperationRun.start!(subject: credential, kind: :validation, context: { fallback_state: "inactive" })
    credential.update!(credential_data: { "api_key" => "replacement-key" })
    credential.validate_async(AiCredentialValidationJob)
    original = credential.reload.attributes

    AiCredentialValidationJob.perform_now(stale)

    assert_predicate stale.reload, :superseded?
    assert_equal original, credential.reload.attributes
  end

  test "#perform should not revive a timed out validation" do
    credential = create(:ai_credential)
    run = create(:operation_run, subject: credential, started_at: 16.minutes.ago,
                                 context: { fallback_state: "inactive" })
    ProviderCredentialValidationTimeoutJob.perform_now(run)
    original = credential.reload.attributes

    AiCredentialValidationJob.perform_now(run)

    assert_predicate run.reload, :timed_out?
    assert_equal original, credential.reload.attributes
  end
end
