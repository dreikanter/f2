require "test_helper"

class RefreshAiModelCatalogsJobTest < ActiveJob::TestCase
  test "#perform should refresh only missing or stale active catalogs" do
    missing = create(:ai_credential, :active)
    stale = create(:ai_credential, :active, models_refreshed_at: 2.days.ago)
    create(:ai_credential, :inactive)
    create(:ai_credential, :active, models_refreshed_at: 1.hour.ago)

    assert_enqueued_jobs 2, only: AiModelCatalogRefreshJob do
      RefreshAiModelCatalogsJob.perform_now
    end

    assert_enqueued_with(job: AiModelCatalogRefreshJob, args: [missing.active_operation_run(:models_refresh)])
    assert_enqueued_with(job: AiModelCatalogRefreshJob, args: [stale.active_operation_run(:models_refresh)])
  end
end
