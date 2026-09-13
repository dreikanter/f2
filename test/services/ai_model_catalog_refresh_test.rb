require "test_helper"

class AiModelCatalogRefreshTest < ActiveSupport::TestCase
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

  test "#call should leave a superseded run and its replacement unchanged" do
    old = OperationRun.start!(subject: openai_credential, kind: :models_refresh)
    current = OperationRun.start!(subject: openai_credential, kind: :models_refresh)
    original = openai_credential.attributes

    AiModelCatalogRefresh.new(old).call

    assert_predicate old.reload, :superseded?
    assert_predicate current.reload, :running?
    assert_equal original, openai_credential.reload.attributes
  end

  test "#call should time out an expired refresh before requesting models" do
    run = openai_credential.refresh_models_async(force: true)
    original = openai_credential.attributes

    travel_to run.deadline_at + 1.second do
      AiModelCatalogRefresh.new(run).call
    end

    assert_predicate run.reload, :timed_out?
    assert_equal original, openai_credential.reload.attributes
  end

  test "#call should retain the snapshot on malformed listing" do
    original = openai_credential.attributes
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "malformed")
    run = openai_credential.refresh_models_async(force: true)

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :failed?
    expected_context = {
      "error" => "OpenAI returned an invalid model list.",
      "category" => "malformed"
    }
    assert_equal expected_context, run.context
    assert_equal original, openai_credential.reload.attributes
  end

  test "#call should retain the snapshot and enabled feeds on transient failure" do
    feed = create(:feed, :enabled, user: openai_credential.user, ai_credential: openai_credential)
    original = openai_credential.attributes
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "unavailable", status: 503)
    run = openai_credential.refresh_models_async(force: true)

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :failed?
    expected_context = {
      "error" => "Couldn't list OpenAI models (HTTP 503). Try again later.",
      "category" => "provider",
      "status" => 503
    }
    assert_equal expected_context, run.context
    assert_equal original, openai_credential.reload.attributes
    assert_predicate feed.reload, :enabled?
  end

  test "#call should deactivate only the current rejected key" do
    feed = create(:feed, :enabled, user: openai_credential.user, ai_credential: openai_credential)
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "invalid_key", status: 401)
    run = openai_credential.refresh_models_async(force: true)

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :failed?
    assert_not_predicate openai_credential.reload, :active?
    assert_predicate feed.reload, :disabled?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
    expected_context = {
      "error" => "OpenAI rejected this API key. Check or replace it.",
      "category" => "invalid_key",
      "status" => 401
    }
    assert_equal expected_context, run.context
    assert_equal expected_context.fetch("error"), openai_credential.last_error
  end

  test "#call should not replace the catalog after key rotation" do
    run = openai_credential.refresh_models_async(force: true)
    stub_openai_models(key: openai_credential.credential_data["api_key"]) do
      AiCredential.find(openai_credential.id).update!(credential_data: { "api_key" => "replacement-key" })
    end

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :superseded?
    assert_not_predicate openai_credential.reload, :active?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
  end

  test "#call should discard a rejection when another credential field changes" do
    run = openai_credential.refresh_models_async(force: true)
    stub_openai_models(key: openai_credential.credential_data.fetch("api_key"), fixture: "invalid_key", status: 401) do
      current = AiCredential.find(openai_credential.id)
      current.update!(credential_data: current.credential_data.merge("organization_id" => "another-organization"))
    end

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :superseded?
    assert_not_predicate openai_credential.reload, :active?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
    assert_not Event.exists?(subject: openai_credential, type: "ai_credential_deactivated")
    assert_empty run.context
  end

  test "#call should discard a response after timeout" do
    run = openai_credential.refresh_models_async(force: true)
    original = openai_credential.attributes
    stub_openai_models(key: openai_credential.credential_data["api_key"]) { run.timeout! }

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :timed_out?
    assert_equal original, openai_credential.reload.attributes
  end

  test "#call should discard a response received after its deadline" do
    run = openai_credential.refresh_models_async(force: true)
    original = openai_credential.attributes
    stub_openai_models(key: openai_credential.credential_data["api_key"]) { travel_to run.deadline_at + 1.second }

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :timed_out?
    assert_equal original, openai_credential.reload.attributes
  end

  test "#call should preserve a newer validation catalog after a late success" do
    run = openai_credential.refresh_models_async(force: true)
    key = openai_credential.credential_data.fetch("api_key")
    stub_openai_models(key: key) do
      stub_openai_models(key: key, fixture: "empty")
      validation_run = openai_credential.validate_async(AiCredentialValidationJob)
      AiCredentialValidation.new(validation_run).call
    end

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :superseded?
    assert_empty openai_credential.reload.available_models
  end

  test "#call should not deactivate a credential after newer validation succeeds" do
    feed = create(:feed, :enabled, user: openai_credential.user, ai_credential: openai_credential)
    run = openai_credential.refresh_models_async(force: true)
    key = openai_credential.credential_data.fetch("api_key")
    stub_openai_models(key: key, fixture: "invalid_key", status: 401) do
      stub_openai_models(key: key, fixture: "empty")
      validation_run = openai_credential.validate_async(AiCredentialValidationJob)
      AiCredentialValidation.new(validation_run).call
    end

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :superseded?
    assert_predicate openai_credential.reload, :active?
    assert_predicate feed.reload, :enabled?
    assert_empty run.context
  end
end
