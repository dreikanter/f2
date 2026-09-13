require "test_helper"

class RefreshAiModelCatalogsJobTest < ActiveJob::TestCase
  test "#perform should refresh only stale active OpenAI catalogs" do
    create(:ai_credential, :active, provider: "openai")
    create(:ai_credential, :inactive, provider: "openai")
    create(:ai_credential, :active, provider: "openai", models_refreshed_at: 1.hour.ago)

    assert_enqueued_jobs 1, only: AiModelCatalogRefreshJob do
      RefreshAiModelCatalogsJob.perform_now
    end
    assert_not_requested :any, /./
  end
end
