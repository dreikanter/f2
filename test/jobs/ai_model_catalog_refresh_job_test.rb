require "test_helper"

class AiModelCatalogRefreshJobTest < ActiveJob::TestCase
  include OpenaiModelsTestHelpers

  def credential
    @credential ||= create(:ai_credential, :active, available_models: [{ "id" => "saved-model" }])
  end

  test "#perform should settle pending work and preserve the saved catalog and key" do
    run = OperationRun.start!(subject: credential, kind: :models_refresh, timeout: 15.minutes)
    original = credential.attributes

    AiModelCatalogRefreshJob.perform_now(run)

    assert_predicate run.reload, :failed?
    assert_equal AiModelCatalog::UNAVAILABLE_MESSAGE, run.context["error"]
    assert_equal original, credential.reload.attributes
    assert_not_requested :any, /./
  end

  test "#refresh_models_async should reject an unavailable provider without creating work" do
    assert_no_enqueued_jobs do
      assert_no_difference "OperationRun.count" do
        assert_nil credential.refresh_models_async(force: true)
      end
    end
    assert_not credential.models_refreshing?
    assert_equal ["saved-model"], credential.reload.available_models.pluck("id")
  end

  test "#perform should skip automatic catalog scheduling for unsupported providers" do
    credential
    assert_no_enqueued_jobs do
      assert_no_difference -> { OperationRun.count } do
        RefreshAiModelCatalogsJob.perform_now
      end
    end
    assert_not_requested :any, /./
  end

  test "#perform should leave a superseded run and its replacement unchanged" do
    old = OperationRun.start!(subject: openai_credential, kind: :models_refresh)
    current = OperationRun.start!(subject: openai_credential, kind: :models_refresh)
    current.fail!

    AiModelCatalogRefreshJob.perform_now(old)
    AiModelCatalogTimeoutJob.perform_now(current)

    assert_predicate old.reload, :superseded?
    assert_predicate current.reload, :failed?
  end

  def openai_credential
    @openai_credential ||= create(:ai_credential, :active, provider: "openai",
                                                            available_models: [{ "id" => "saved-model" }])
  end

  test "#perform should update the snapshot without changing credential validation" do
    original = openai_credential.attributes.except("available_models", "models_refreshed_at", "updated_at")
    stub_openai_models(key: openai_credential.credential_data["api_key"])
    run = openai_credential.refresh_models_async(force: true)
    assert_enqueued_with(job: AiModelCatalogRefreshJob, args: [run])
    assert_enqueued_with(job: AiModelCatalogTimeoutJob, args: [run], at: run.deadline_at)

    AiModelCatalogRefreshJob.perform_now(run)

    assert_predicate run.reload, :succeeded?
    assert_not openai_credential.reload.models_refreshing?
    assert openai_credential.supports_model?("future-openai-model")
    assert_equal original, openai_credential.attributes.slice(*original.keys)
  end

  test "#perform should retain the snapshot on malformed listing" do
    original = openai_credential.attributes
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "malformed")
    run = openai_credential.refresh_models_async(force: true)

    AiModelCatalogRefreshJob.perform_now(run)

    assert_predicate run.reload, :failed?
    assert_equal "malformed", run.context["category"]
    assert_equal original, openai_credential.reload.attributes
  end

  test "#perform should retain the snapshot and enabled feeds on transient failure" do
    feed = create(:feed, :enabled, user: openai_credential.user, ai_credential: openai_credential)
    original = openai_credential.attributes
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "unavailable", status: 503)
    run = openai_credential.refresh_models_async(force: true)

    AiModelCatalogRefreshJob.perform_now(run)

    assert_predicate run.reload, :failed?
    assert_equal 503, run.context["status"]
    assert_equal original, openai_credential.reload.attributes
    assert_predicate feed.reload, :enabled?
  end

  test "#perform should deactivate only the current rejected key" do
    feed = create(:feed, :enabled, user: openai_credential.user, ai_credential: openai_credential)
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "invalid_key", status: 401)
    run = openai_credential.refresh_models_async(force: true)

    AiModelCatalogRefreshJob.perform_now(run)

    assert_predicate run.reload, :failed?
    assert_predicate openai_credential.reload, :inactive?
    assert_predicate feed.reload, :disabled?
    assert_equal ["saved-model"], openai_credential.available_models.pluck("id")
  end

  test "#perform should not replace the catalog after key rotation" do
    run = openai_credential.refresh_models_async(force: true)
    stub_openai_models(key: openai_credential.credential_data["api_key"]) do
      AiCredential.find(openai_credential.id).update!(credential_data: { "api_key" => "replacement-key" })
    end

    AiModelCatalogRefreshJob.perform_now(run)

    assert_predicate run.reload, :failed?
    assert_equal ["saved-model"], openai_credential.reload.available_models.pluck("id")
  end

  test "#perform should not deactivate a replaced key" do
    run = openai_credential.refresh_models_async(force: true)
    stub_openai_models(key: openai_credential.credential_data["api_key"], fixture: "invalid_key", status: 401) do
      AiCredential.find(openai_credential.id).update!(credential_data: { "api_key" => "replacement-key" })
    end

    AiModelCatalogRefreshJob.perform_now(run)

    assert_predicate run.reload, :failed?
    assert_predicate openai_credential.reload, :active?
    assert_not Event.exists?(subject: openai_credential, type: "ai_credential_deactivated")
  end

  test "#perform should discard a response after timeout" do
    run = openai_credential.refresh_models_async(force: true)
    stub_openai_models(key: openai_credential.credential_data["api_key"]) { AiModelCatalogTimeoutJob.perform_now(run) }

    AiModelCatalogRefreshJob.perform_now(run)

    assert_predicate run.reload, :timed_out?
    assert_equal ["saved-model"], openai_credential.reload.available_models.pluck("id")
  end

  test "#refresh_models_async should reuse an active run and throttle automatic retries" do
    run = openai_credential.refresh_models_async
    assert_no_enqueued_jobs { assert_equal run, openai_credential.refresh_models_async(force: true) }
    run.fail!

    assert_no_enqueued_jobs { assert_nil openai_credential.refresh_models_async }
    assert_enqueued_with(job: AiModelCatalogRefreshJob) { openai_credential.refresh_models_async(force: true) }
  end

  test "#perform should refresh only stale active OpenAI catalogs" do
    openai_credential
    credential
    create(:ai_credential, :inactive, provider: "openai")
    create(:ai_credential, :active, provider: "openai", models_refreshed_at: 1.hour.ago)

    assert_enqueued_jobs 1, only: AiModelCatalogRefreshJob do
      RefreshAiModelCatalogsJob.perform_now
    end
    assert_not_requested :any, /./
  end
end
