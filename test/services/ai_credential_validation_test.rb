require "test_helper"

class AiCredentialValidationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include OpenaiModelsTestHelpers

  def openai_credential
    @openai_credential ||= create(
      :ai_credential,
      :active,
      available_models: [{ "id" => "saved-model" }],
      models_refreshed_at: 1.day.ago
    )
  end

  test "#call should not let a superseded run overwrite a replacement key" do
    credential = create(:ai_credential, :active)
    stale = OperationRun.start!(subject: credential, kind: :validation)
    credential.update!(credential_data: { "api_key" => "replacement-key" })
    credential.validate_async(AiCredentialValidationJob)
    original = credential.reload.attributes

    AiCredentialValidation.new(stale).call

    assert_predicate stale.reload, :superseded?
    assert_equal original, credential.reload.attributes
  end

  test "#call should not revive a timed out validation" do
    credential = create(:ai_credential)
    run = credential.validate_async(AiCredentialValidationJob)
    validation = AiCredentialValidation.new(run)
    run.timeout!
    original = credential.reload.attributes

    validation.call

    assert_predicate run.reload, :timed_out?
    assert_equal original, credential.reload.attributes
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
  end

  test "#call should deactivate a confirmed rejected key and disable its feeds" do
    feed = create(:feed, :enabled, user: openai_credential.user, ai_credential: openai_credential)
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "invalid_key", status: 401)
    run = openai_credential.validate_async(AiCredentialValidationJob)

    AiCredentialValidation.new(run).call

    assert_predicate run.reload, :failed?
    assert_not_predicate openai_credential.reload, :active?
    assert_predicate feed.reload, :disabled?
    assert Event.exists?(subject: openai_credential, type: "ai_credential_deactivated")
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
    expected_context = {
      "error" => "OpenAI rejected this API key. Check or replace it.",
      "category" => "invalid_key",
      "status" => 401
    }
    assert_equal expected_context, run.context
    assert_equal expected_context.fetch("error"), openai_credential.last_error
  end

  test "#call should preserve the prior state and snapshot on an IP restriction" do
    feed = create(:feed, :enabled, user: openai_credential.user, ai_credential: openai_credential)
    original_timestamp = openai_credential.last_validated_at
    original_refresh = openai_credential.models_refreshed_at
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "ip_restriction", status: 401)
    run = openai_credential.validate_async(AiCredentialValidationJob)

    AiCredentialValidation.new(run).call

    assert_predicate run.reload, :failed?
    assert_predicate openai_credential.reload, :active?
    assert_predicate feed.reload, :enabled?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
    assert_equal original_timestamp, openai_credential.last_validated_at
    assert_equal original_refresh, openai_credential.models_refreshed_at
    assert_not Event.exists?(subject: openai_credential, type: "ai_credential_deactivated")
  end

  test "#call should leave a new key inactive after a transient failure" do
    credential = create(:ai_credential)
    stub_openai_models(key: credential.credential_data["api_key"], fixture: "unavailable", status: 503)
    run = credential.validate_async(AiCredentialValidationJob)

    AiCredentialValidation.new(run).call

    assert_predicate run.reload, :failed?
    assert_not_predicate credential.reload, :active?
    assert_empty credential.available_models
    assert_nil credential.last_validated_at
    assert_not Event.exists?(subject: credential, type: "ai_credential_deactivated")
    expected_context = {
      "error" => "Couldn't list OpenAI models (HTTP 503). Try again later.",
      "category" => "provider",
      "status" => 503
    }
    assert_equal expected_context, run.context
    assert_equal expected_context.fetch("error"), credential.last_error
  end

  test "#call should discard a catalog when another credential field changes" do
    run = openai_credential.validate_async(AiCredentialValidationJob)
    stub_openai_models(key: openai_credential.credential_data.fetch("api_key")) do
      current = AiCredential.find(openai_credential.id)
      current.update!(credential_data: current.credential_data.merge("organization_id" => "another-organization"))
    end

    AiCredentialValidation.new(run).call

    assert_predicate run.reload, :superseded?
    assert_not_predicate openai_credential.reload, :active?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
  end

  test "#call should not deactivate a validated replacement key on late rejection" do
    run = openai_credential.validate_async(AiCredentialValidationJob)
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "invalid_key", status: 401) do
      replacement = AiCredential.find(openai_credential.id)
      replacement.update!(credential_data: { "api_key" => "replacement-key" })
      stub_openai_models(key: "replacement-key", fixture: "empty")
      AiCredentialValidation.new(replacement.validate_async(AiCredentialValidationJob)).call
    end

    AiCredentialValidation.new(run).call

    assert_predicate run.reload, :superseded?
    assert_predicate openai_credential.reload, :active?
    assert_empty openai_credential.available_models
    assert_not Event.exists?(subject: openai_credential, type: "ai_credential_deactivated")
  end

  test "#call should discard a response received after its deadline" do
    run = openai_credential.validate_async(AiCredentialValidationJob)
    stub_openai_models(key: openai_credential.credential_data["api_key"]) { travel_to run.deadline_at + 1.second }

    AiCredentialValidation.new(run).call

    assert_predicate run.reload, :timed_out?
    assert_predicate openai_credential.reload, :active?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
  end
end
