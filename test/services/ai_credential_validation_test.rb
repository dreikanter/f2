require "test_helper"

class AiCredentialValidationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include OpenaiModelsTestHelpers

  test "#call should not let a superseded run overwrite a replacement key" do
    credential = create(:ai_credential, :active)
    stale = OperationRun.start!(subject: credential, kind: :validation, context: { fallback_state: "inactive" })
    credential.update!(credential_data: { "api_key" => "replacement-key" })
    credential.validate_async(AiCredentialValidationJob)
    original = credential.reload.attributes

    AiCredentialValidation.new(stale).call

    assert_predicate stale.reload, :superseded?
    assert_equal original, credential.reload.attributes
  end

  test "#call should not revive a timed out validation" do
    credential = create(:ai_credential)
    run = create(:operation_run, subject: credential, started_at: 16.minutes.ago,
                                 context: { fallback_state: "inactive" })
    credential.timeout_validation!(run: run)
    original = credential.reload.attributes

    AiCredentialValidation.new(run).call

    assert_predicate run.reload, :timed_out?
    assert_equal original, credential.reload.attributes
  end

  def openai_credential
    @openai_credential ||= create(:ai_credential, :active, provider: "openai",
                                                            available_models: [{ "id" => "saved-model" }])
  end

  test "#call should accept an authenticated empty catalog" do
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "empty")
    run = openai_credential.validate_async(AiCredentialValidationJob)

    AiCredentialValidation.new(run).call

    assert_predicate run.reload, :succeeded?
    assert_predicate openai_credential.reload, :active?
    assert_empty openai_credential.available_models
  end

  test "#call should time out an expired validation before requesting models" do
    run = openai_credential.validate_async(AiCredentialValidationJob)

    travel_to run.deadline_at + 1.second do
      AiCredentialValidation.new(run).call
    end

    assert_predicate run.reload, :timed_out?
    assert_predicate openai_credential.reload, :active?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
    assert_not_requested :any, /./
  end

  test "#call should deactivate a confirmed rejected key and disable its feeds" do
    feed = create(:feed, :enabled, user: openai_credential.user, ai_credential: openai_credential)
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "invalid_key", status: 401)
    run = openai_credential.validate_async(AiCredentialValidationJob)

    AiCredentialValidation.new(run).call

    assert_predicate run.reload, :failed?
    assert_predicate openai_credential.reload, :inactive?
    assert_predicate feed.reload, :disabled?
    assert Event.exists?(subject: openai_credential, type: "ai_credential_deactivated")
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
    assert_not_includes openai_credential.last_error, "sk-sample-secret"
    assert_equal({ "fallback_state" => "active", "error" => "OpenAI rejected this API key. Check or replace it.",
                   "category" => "invalid_key", "status" => 401 }, run.context)
  end

  test "#call should preserve the prior state and snapshot on an IP restriction" do
    feed = create(:feed, :enabled, user: openai_credential.user, ai_credential: openai_credential)
    original_timestamp = openai_credential.last_validated_at
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "ip_restriction", status: 401)
    run = openai_credential.validate_async(AiCredentialValidationJob)

    AiCredentialValidation.new(run).call

    assert_predicate run.reload, :failed?
    assert_predicate openai_credential.reload, :active?
    assert_predicate feed.reload, :enabled?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
    assert_equal original_timestamp, openai_credential.last_validated_at
    assert_not Event.exists?(subject: openai_credential, type: "ai_credential_deactivated")
  end

  test "#call should leave a new key inactive after a transient failure" do
    openai_credential.update!(state: :pending)
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "unavailable", status: 503)
    run = openai_credential.validate_async(AiCredentialValidationJob)

    AiCredentialValidation.new(run).call

    assert_predicate run.reload, :failed?
    assert_predicate openai_credential.reload, :inactive?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
    assert_not Event.exists?(subject: openai_credential, type: "ai_credential_deactivated")
    assert_equal({ "fallback_state" => "inactive", "error" => "Couldn't list OpenAI models (HTTP 503). Try again later.",
                   "category" => "provider", "status" => 503 }, run.context)
    assert_equal run.context["error"], openai_credential.last_error
  end

  test "#call should reject a success received for a replaced key" do
    run = openai_credential.validate_async(AiCredentialValidationJob)
    stub_openai_models(key: openai_credential.credential_data["api_key"]) do
      AiCredential.find(openai_credential.id).update!(credential_data: { "api_key" => "replacement-key" })
    end

    AiCredentialValidation.new(run).call

    assert_predicate run.reload, :failed?
    assert_equal "replacement-key", openai_credential.reload.credential_data["api_key"]
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
  end

  test "#call should not deactivate a replacement key on late rejection" do
    run = openai_credential.validate_async(AiCredentialValidationJob)
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "invalid_key", status: 401) do
      AiCredential.find(openai_credential.id).update!(state: :active, credential_data: { "api_key" => "replacement-key" })
    end

    AiCredentialValidation.new(run).call

    assert_predicate run.reload, :failed?
    assert_predicate openai_credential.reload, :active?
    assert_not Event.exists?(subject: openai_credential, type: "ai_credential_deactivated")
    assert_equal({ "fallback_state" => "active" }, run.context)
  end

  test "#call should discard a response received after its deadline" do
    run = openai_credential.validate_async(AiCredentialValidationJob)
    stub_openai_models(key: openai_credential.credential_data["api_key"]) { travel_to run.deadline_at + 1.second }

    AiCredentialValidation.new(run).call

    assert_predicate run.reload, :timed_out?
    assert_predicate openai_credential.reload, :active?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
  ensure
    travel_back
  end
end
