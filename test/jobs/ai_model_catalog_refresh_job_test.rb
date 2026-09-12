require "test_helper"

class AiModelCatalogRefreshJobTest < ActiveJob::TestCase
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

  test "#refresh_models_async should settle an explicit request without queued work" do
    assert_no_enqueued_jobs do
      run = credential.refresh_models_async(force: true)
      assert_predicate run, :failed?
    end
    assert_not credential.models_refreshing?
    assert_equal ["saved-model"], credential.reload.available_models.pluck("id")
  end

  test "#perform should stop automatic catalog scheduling" do
    credential
    assert_no_enqueued_jobs do
      assert_no_difference -> { OperationRun.count } do
        RefreshAiModelCatalogsJob.perform_now
      end
    end
    assert_not_requested :any, /./
  end

  test "#perform should leave a superseded run and its replacement unchanged" do
    old = OperationRun.start!(subject: credential, kind: :models_refresh)
    current = credential.refresh_models_async(force: true)

    AiModelCatalogRefreshJob.perform_now(old)
    AiModelCatalogTimeoutJob.perform_now(current)

    assert_predicate old.reload, :superseded?
    assert_predicate current.reload, :failed?
  end
end
