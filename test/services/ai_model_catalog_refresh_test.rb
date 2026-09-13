require "test_helper"

class AiModelCatalogRefreshTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include OpenaiModelsTestHelpers

  test "#call should leave a superseded run and its replacement unchanged" do
    old = OperationRun.start!(subject: openai_credential, kind: :models_refresh)
    current = OperationRun.start!(subject: openai_credential, kind: :models_refresh)
    current.fail!

    AiModelCatalogRefresh.new(old).call
    current.timeout!

    assert_predicate old.reload, :superseded?
    assert_predicate current.reload, :failed?
  end

  def openai_credential
    @openai_credential ||= create(:ai_credential, :active, provider: "openai",
                                                            available_models: [{ "id" => "saved-model" }])
  end

  test "#call should retain the snapshot on malformed listing" do
    original = openai_credential.attributes
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "malformed")
    run = openai_credential.refresh_models_async(force: true)

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :failed?
    assert_equal({ "error" => "OpenAI returned an invalid model list.", "category" => "malformed" }, run.context)
    assert_equal original, openai_credential.reload.attributes
  end

  test "#call should retain the snapshot and enabled feeds on transient failure" do
    feed = create(:feed, :enabled, user: openai_credential.user, ai_credential: openai_credential)
    original = openai_credential.attributes
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "unavailable", status: 503)
    run = openai_credential.refresh_models_async(force: true)

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :failed?
    assert_equal({ "error" => "Couldn't list OpenAI models (HTTP 503). Try again later.",
                   "category" => "provider", "status" => 503 }, run.context)
    assert_equal original, openai_credential.reload.attributes
    assert_predicate feed.reload, :enabled?
  end

  test "#call should deactivate only the current rejected key" do
    feed = create(:feed, :enabled, user: openai_credential.user, ai_credential: openai_credential)
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "invalid_key", status: 401)
    run = openai_credential.refresh_models_async(force: true)

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :failed?
    assert_predicate openai_credential.reload, :inactive?
    assert_predicate feed.reload, :disabled?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
    assert_equal({ "error" => "OpenAI rejected this API key. Check or replace it.",
                   "category" => "invalid_key", "status" => 401 }, run.context)
    assert_equal run.context["error"], openai_credential.last_error
  end

  test "#call should not replace the catalog after key rotation" do
    run = openai_credential.refresh_models_async(force: true)
    stub_openai_models(key: openai_credential.credential_data["api_key"]) do
      AiCredential.find(openai_credential.id).update!(credential_data: { "api_key" => "replacement-key" })
    end

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :failed?
    assert_equal ["saved-model"], openai_credential.reload.available_models.pluck("id")
  end

  test "#call should not deactivate a replaced key" do
    run = openai_credential.refresh_models_async(force: true)
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "invalid_key", status: 401) do
      AiCredential.find(openai_credential.id).update!(credential_data: { "api_key" => "replacement-key" })
    end

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :failed?
    assert_predicate openai_credential.reload, :active?
    assert_not Event.exists?(subject: openai_credential, type: "ai_credential_deactivated")
    assert_empty run.context
  end

  test "#call should discard a response after timeout" do
    run = openai_credential.refresh_models_async(force: true)
    stub_openai_models(key: openai_credential.credential_data["api_key"]) { run.timeout! }

    AiModelCatalogRefresh.new(run).call

    assert_predicate run.reload, :timed_out?
    assert_equal ["saved-model"], openai_credential.reload.available_models.pluck("id")
  end
end
