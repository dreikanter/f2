require "test_helper"

class AiCredentialValidationJobTest < ActiveJob::TestCase
  include OpenaiModelsTestHelpers

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

  test "#perform should accept an authenticated empty catalog" do
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "empty")
    run = openai_credential.validate_async(AiCredentialValidationJob)

    AiCredentialValidationJob.perform_now(run)

    assert_predicate run.reload, :succeeded?
    assert_predicate openai_credential.reload, :active?
    assert_empty openai_credential.available_models
  end

  test "#perform should deactivate a confirmed rejected key and disable its feeds" do
    feed = create(:feed, :enabled, user: openai_credential.user, ai_credential: openai_credential)
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "invalid_key", status: 401)
    run = openai_credential.validate_async(AiCredentialValidationJob)

    AiCredentialValidationJob.perform_now(run)

    assert_predicate run.reload, :failed?
    assert_predicate openai_credential.reload, :inactive?
    assert_predicate feed.reload, :disabled?
    assert Event.exists?(subject: openai_credential, type: "ai_credential_deactivated")
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
    assert_not_includes openai_credential.last_error, "sk-sample-secret"
  end

  test "#perform should preserve the prior state and snapshot on an IP restriction" do
    feed = create(:feed, :enabled, user: openai_credential.user, ai_credential: openai_credential)
    original_timestamp = openai_credential.last_validated_at
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "ip_restriction", status: 401)
    run = openai_credential.validate_async(AiCredentialValidationJob)

    AiCredentialValidationJob.perform_now(run)

    assert_predicate run.reload, :failed?
    assert_predicate openai_credential.reload, :active?
    assert_predicate feed.reload, :enabled?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
    assert_equal original_timestamp, openai_credential.last_validated_at
    assert_not Event.exists?(subject: openai_credential, type: "ai_credential_deactivated")
  end

  test "#perform should leave a new key inactive after a transient failure" do
    openai_credential.update!(state: :pending)
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "unavailable", status: 503)
    run = openai_credential.validate_async(AiCredentialValidationJob)

    AiCredentialValidationJob.perform_now(run)

    assert_predicate run.reload, :failed?
    assert_predicate openai_credential.reload, :inactive?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
    assert_not Event.exists?(subject: openai_credential, type: "ai_credential_deactivated")
  end

  test "#perform should reject a success received for a replaced key" do
    run = openai_credential.validate_async(AiCredentialValidationJob)
    stub_openai_models(key: openai_credential.credential_data["api_key"]) do
      AiCredential.find(openai_credential.id).update!(credential_data: { "api_key" => "replacement-key" })
    end

    AiCredentialValidationJob.perform_now(run)

    assert_predicate run.reload, :failed?
    assert_equal "replacement-key", openai_credential.reload.credential_data["api_key"]
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
  end

  test "#perform should not deactivate a replacement key on late rejection" do
    run = openai_credential.validate_async(AiCredentialValidationJob)
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "invalid_key", status: 401) do
      AiCredential.find(openai_credential.id).update!(state: :active, credential_data: { "api_key" => "replacement-key" })
    end

    AiCredentialValidationJob.perform_now(run)

    assert_predicate run.reload, :failed?
    assert_predicate openai_credential.reload, :active?
    assert_not Event.exists?(subject: openai_credential, type: "ai_credential_deactivated")
  end

  test "#perform should discard a response received after its deadline" do
    run = openai_credential.validate_async(AiCredentialValidationJob)
    stub_openai_models(key: openai_credential.credential_data["api_key"]) { travel_to run.deadline_at + 1.second }

    AiCredentialValidationJob.perform_now(run)

    assert_predicate run.reload, :timed_out?
    assert_predicate openai_credential.reload, :active?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
  ensure
    travel_back
  end
end
